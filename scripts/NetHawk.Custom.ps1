
$EngineScript = Join-Path $PSScriptRoot "NetHawk.ps1"

$UserProfilesDir = Join-Path $Config "profiles-user"
$PortsPath = Join-Path $Config "ports-user.json"
$PortScoutDir = Join-Path $Root "logs\port-scout"
$DefaultTcpCoverage = "80,443,2053,2083,2087,2096,8443"
$DefaultUdpCoverage = "443,19294-19344,50000-50100"

function Ensure-CustomDirs {
    foreach($path in @($Config,$UserProfilesDir,$PortScoutDir)) {
        if(-not(Test-Path -LiteralPath $path)) {
            New-Item -ItemType Directory -Force -Path $path | Out-Null
        }
    }
}

function Normalize-PortSpec([string]$Spec) {
    if([string]::IsNullOrWhiteSpace($Spec)) { return "" }
    $items=@()

    foreach($token in ($Spec -split '[,;\s]+' | Where-Object { $_ })) {
        if($token -match '^(\d+)-(\d+)$') {
            $a=[int]$matches[1]
            $b=[int]$matches[2]
            if($a -lt 1 -or $b -gt 65535 -or $a -gt $b) { throw "Некорректный диапазон: $token" }
            $items += [pscustomobject]@{Start=$a;End=$b;Text=("$a-$b")}
        }
        elseif($token -match '^\d+$') {
            $p=[int]$token
            if($p -lt 1 -or $p -gt 65535) { throw "Некорректный порт: $token" }
            $items += [pscustomobject]@{Start=$p;End=$p;Text=[string]$p}
        }
        else {
            throw "Некорректный формат порта: $token"
        }
    }

    return (($items | Sort-Object Start,End | Group-Object Text | ForEach-Object { $_.Name }) -join ",")
}

function Merge-PortSpecs([string[]]$Specs) {
    $value=(($Specs | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ",")
    if([string]::IsNullOrWhiteSpace($value)) { return "" }
    return Normalize-PortSpec $value
}

function Test-PortCovered([int]$Port,[string]$Spec) {
    foreach($token in ($Spec -split ',' | Where-Object { $_ })) {
        if($token -match '^(\d+)-(\d+)$') {
            if($Port -ge [int]$matches[1] -and $Port -le [int]$matches[2]) { return $true }
        }
        elseif($token -match '^\d+$' -and $Port -eq [int]$token) {
            return $true
        }
    }
    return $false
}

function Get-UncoveredPorts([int[]]$Ports,[string]$Coverage) {
    return @($Ports | Sort-Object -Unique | Where-Object { -not (Test-PortCovered $_ $Coverage) })
}

function Get-GlobalPorts {
    Ensure-CustomDirs
    $ports=[ordered]@{TCP="";UDP=""}

    if(Test-Path -LiteralPath $PortsPath) {
        try {
            $j=Get-Content -LiteralPath $PortsPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $ports.TCP=Normalize-PortSpec ([string]$j.TCP)
            $ports.UDP=Normalize-PortSpec ([string]$j.UDP)
        } catch {
            Write-Host "[WARN] ports-user.json повреждён." -ForegroundColor Yellow
        }
    }

    return $ports
}

function Save-GlobalPorts($Ports) {
    Ensure-CustomDirs
    [pscustomobject][ordered]@{
        TCP=Normalize-PortSpec ([string]$Ports.TCP)
        UDP=Normalize-PortSpec ([string]$Ports.UDP)
    } | ConvertTo-Json | Set-Content -LiteralPath $PortsPath -Encoding UTF8
}

function Get-UserProfiles {
    Ensure-CustomDirs
    $result=@()

    foreach($file in @(Get-ChildItem -LiteralPath $UserProfilesDir -File -Filter "*.json" -ErrorAction SilentlyContinue)) {
        try {
            $j=Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            $name=([string]$j.Name).Trim()
            $base=[string]$j.Base

            if(-not $name -or $name -match '[\\/:*?"<>|]' -or -not (Get-ProfileCatalogV2 | Where-Object { $_.Key -ieq $base })) {
                continue
            }

            $result += [pscustomobject]@{
                Key=$name
                Kind="User"
                Base=$base
                TCPAdd=Normalize-PortSpec ([string]$j.TCPAdd)
                UDPAdd=Normalize-PortSpec ([string]$j.UDPAdd)
                RawExtraArgs=[string]$j.RawExtraArgs
                Path=$file.FullName
            }
        } catch {
            Write-Host ("[WARN] Не читается пользовательский профиль {0}" -f $file.Name) -ForegroundColor Yellow
        }
    }

    return @($result | Sort-Object Key)
}

function Save-UserProfile([string]$Name,[string]$Base,[string]$TCPAdd="",[string]$UDPAdd="",[string]$RawExtraArgs="",[string]$Path="") {
    Ensure-CustomDirs
    $nameClean=$Name.Trim()

    if(-not $nameClean -or $nameClean -match '[\\/:*?"<>|]' -or $nameClean.Length -gt 64) {
        throw "Недопустимое имя профиля."
    }
    if(-not (Get-ProfileCatalogV2 | Where-Object { $_.Key -ieq $Base })) {
        throw "Неизвестный базовый профиль: $Base"
    }
    if(Get-ProfileCatalogV2 | Where-Object { $_.Key -ieq $nameClean }) {
        throw "Такое имя уже занято upstream-профилем."
    }

    if(-not $Path) {
        $Path=Join-Path $UserProfilesDir ($nameClean+".json")
        if(Test-Path -LiteralPath $Path) { throw "Профиль '$nameClean' уже существует." }
    }

    [pscustomobject][ordered]@{
        Name=$nameClean
        Base=$Base
        TCPAdd=Normalize-PortSpec $TCPAdd
        UDPAdd=Normalize-PortSpec $UDPAdd
        RawExtraArgs=$RawExtraArgs
    } | ConvertTo-Json | Set-Content -LiteralPath $Path -Encoding UTF8

    return $Path
}

function Get-AllProfiles {
    $result=@()

    foreach($p in @(Get-ProfileCatalogV2)) {
        $result += [pscustomobject]@{Key=$p.Key;Kind="Upstream";Base=$p.Key;TCPAdd="";UDPAdd="";RawExtraArgs="";Path=$null}
    }

    $result += @(Get-UserProfiles)
    return @($result)
}

function Resolve-NetHawkProfile([string]$Name) {
    $profile=Get-AllProfiles | Where-Object { $_.Key -ieq $Name } | Select-Object -First 1
    if($null -eq $profile) { throw "Неизвестный профиль: $Name" }
    return $profile
}

function Get-V2GamePorts($Settings,[string]$ProfileName="") {
    $tcp=""
    $udp=""

    switch($Settings.GameFilter) {
        "all" {$tcp="1024-65535";$udp="1024-65535"}
        "tcp" {$tcp="1024-65535"}
        "udp" {$udp="1024-65535"}
    }

    $global=Get-GlobalPorts
    $tcp=Merge-PortSpecs @($tcp,$global.TCP)
    $udp=Merge-PortSpecs @($udp,$global.UDP)

    if($ProfileName) {
        $profile=Resolve-NetHawkProfile $ProfileName
        if($profile.Kind -eq "User") {
            $tcp=Merge-PortSpecs @($tcp,$profile.TCPAdd)
            $udp=Merge-PortSpecs @($udp,$profile.UDPAdd)
        }
    }

    $both=Merge-PortSpecs @($tcp,$udp)
    if(-not $tcp) {$tcp="12"}
    if(-not $udp) {$udp="12"}
    if(-not $both) {$both="12"}

    return [pscustomobject]@{TCP=$tcp;UDP=$udp;Both=$both}
}

function Get-ProfileArguments([string]$Name) {
    Ensure-V2UserFiles
    Ensure-CustomDirs
    Assert-Runtime

    $profile=Resolve-NetHawkProfile $Name
    $path=Join-Path $Profiles ($profile.Base+".profile")
    $lines=Get-Content -LiteralPath $path
    $start=-1

    for($i=0;$i -lt $lines.Count;$i++) {
        if($lines[$i] -match "winws\.exe") {$start=$i;break}
    }

    if($start -lt 0) { throw "В профиле $($profile.Base) не найден winws.exe." }

    $parts=New-Object System.Collections.Generic.List[string]
    $rx=New-Object Text.RegularExpressions.Regex('^.*?winws\.exe"?\s*',[Text.RegularExpressions.RegexOptions]::IgnoreCase)

    for($i=$start;$i -lt $lines.Count;$i++) {
        $line=[string]$lines[$i]
        if($i -eq $start) {$line=$rx.Replace($line,"")}

        $part=$line.Trim()
        $continued=$part.EndsWith("^")
        if($continued) {$part=$part.Substring(0,$part.Length-1).Trim()}
        if($part) {$parts.Add($part)}
        if(-not $continued) {break}
    }

    $args=$parts -join " "
    $settings=Get-V2Settings
    $game=Get-V2GamePorts $settings $Name
    $ipset=Get-V2IPSetPath $settings
    $discordFake=Join-Path $Bin $settings.DiscordFake
    $gameFake=Join-Path $Bin $settings.GameFake

    if(-not(Test-Path -LiteralPath $discordFake)) {$discordFake=Join-Path $Bin "ACTIVE_DISCORD_UDP.bin"}
    if(-not(Test-Path -LiteralPath $gameFake)) {$gameFake=Join-Path $Bin "ACTIVE_GAME_UDP.bin"}

    if($profile.Kind -eq "User" -and $profile.RawExtraArgs) {
        $args += " " + $profile.RawExtraArgs.Trim()
    }

    $args=$args.Replace('"%LISTS%ipset-all.txt"',('"'+$ipset+'"'))
    $args=$args.Replace('"%BIN%ACTIVE_DISCORD_UDP.bin"',('"'+$discordFake+'"'))
    $args=$args.Replace('"%BIN%ACTIVE_GAME_UDP.bin"',('"'+$gameFake+'"'))
    $args=$args.Replace("%GameFilterTCP%",$game.TCP)
    $args=$args.Replace("%GameFilterUDP%",$game.UDP)
    $args=$args.Replace("%GameFilter%",$game.Both)
    $args=$args.Replace("%BIN%",($Bin.TrimEnd("\")+"\"))
    $args=$args.Replace("%LISTS%",($Lists.TrimEnd("\")+"\"))

    return $args
}

function Select-V2Profile {
    $profiles=@(Get-AllProfiles)
    Write-Host ""

    for($i=0;$i -lt $profiles.Count;$i++) {
        $tag=if($profiles[$i].Kind -eq "User"){"USER"}else{"UP"}
        $base=if($profiles[$i].Kind -eq "User"){(" <- "+$profiles[$i].Base)}else{""}
        Write-Host ("  {0,2}. [{1}] {2}{3}" -f ($i+1),$tag,$profiles[$i].Key,$base)
    }

    Write-Host "   0. Назад"
    $value=Read-Host "Профиль"
    $number=0
    if(-not[int]::TryParse($value,[ref]$number) -or $number -lt 1 -or $number -gt $profiles.Count) {return $null}
    return $profiles[$number-1].Key
}

function Select-UpstreamProfile {
    $profiles=@(Get-ProfileCatalogV2)
    for($i=0;$i -lt $profiles.Count;$i++) {
        Write-Host ("  {0,2}. {1}" -f ($i+1),$profiles[$i].Key)
    }
    Write-Host "   0. Назад"

    $value=Read-Host "Базовый профиль"
    $number=0
    if(-not[int]::TryParse($value,[ref]$number) -or $number -lt 1 -or $number -gt $profiles.Count) {return $null}
    return $profiles[$number-1].Key
}

function Select-UserProfile {
    $profiles=@(Get-UserProfiles)
    if($profiles.Count -eq 0) {
        Write-Host "[INFO] Пользовательских профилей пока нет." -ForegroundColor DarkGray
        return $null
    }

    for($i=0;$i -lt $profiles.Count;$i++) {
        Write-Host ("  {0,2}. {1} <- {2}" -f ($i+1),$profiles[$i].Key,$profiles[$i].Base)
    }
    Write-Host "   0. Назад"

    $value=Read-Host "Профиль"
    $number=0
    if(-not[int]::TryParse($value,[ref]$number) -or $number -lt 1 -or $number -gt $profiles.Count) {return $null}
    return $profiles[$number-1]
}

function Configure-CustomPorts {
    while($true) {
        Clear-Host
        Show-Header
        $ports=Get-GlobalPorts

        Write-Host "Свои порты для всех профилей" -ForegroundColor Cyan
        Write-Host ("TCP: {0}" -f $(if($ports.TCP){$ports.TCP}else{"—"}))
        Write-Host ("UDP: {0}" -f $(if($ports.UDP){$ports.UDP}else{"—"}))
        Write-Host ""
        Write-Host "1. Задать TCP"
        Write-Host "2. Задать UDP"
        Write-Host "3. Добавить TCP"
        Write-Host "4. Добавить UDP"
        Write-Host "5. Очистить всё"
        Write-Host "0. Назад"

        switch(Read-Host "Выбери") {
            "1" {$ports.TCP=Normalize-PortSpec (Read-Host "TCP");Save-GlobalPorts $ports}
            "2" {$ports.UDP=Normalize-PortSpec (Read-Host "UDP");Save-GlobalPorts $ports}
            "3" {$ports.TCP=Merge-PortSpecs @($ports.TCP,(Read-Host "Добавить TCP"));Save-GlobalPorts $ports}
            "4" {$ports.UDP=Merge-PortSpecs @($ports.UDP,(Read-Host "Добавить UDP"));Save-GlobalPorts $ports}
            "5" {$ports.TCP="";$ports.UDP="";Save-GlobalPorts $ports}
            "0" {return}
        }
    }
}

function Create-UserProfileInteractive([string]$TcpPreset="",[string]$UdpPreset="") {
    Clear-Host
    Show-Header
    Write-Host "Новый пользовательский профиль" -ForegroundColor Cyan

    $base=Select-UpstreamProfile
    if(-not $base) {return}

    $name=Read-Host "Имя"
    if(-not $name) {return}

    $tcp=Read-Host ("TCP + [{0}]" -f $(if($TcpPreset){$TcpPreset}else{"пусто"}))
    if(-not $tcp) {$tcp=$TcpPreset}

    $udp=Read-Host ("UDP + [{0}]" -f $(if($UdpPreset){$UdpPreset}else{"пусто"}))
    if(-not $udp) {$udp=$UdpPreset}

    $raw=Read-Host "Raw Extra Arguments (можно пусто)"
    $path=Save-UserProfile $name $base $tcp $udp $raw
    Write-Host ("[OK] Создан: {0}" -f $path) -ForegroundColor Green
}

function Edit-UserProfile($Profile) {
    while($true) {
        $Profile=Get-UserProfiles | Where-Object { $_.Path -eq $Profile.Path } | Select-Object -First 1
        if(-not $Profile) {return}

        Clear-Host
        Show-Header
        Write-Host ("{0} <- {1}" -f $Profile.Key,$Profile.Base) -ForegroundColor Cyan
        Write-Host ("TCP +: {0}" -f $(if($Profile.TCPAdd){$Profile.TCPAdd}else{"—"}))
        Write-Host ("UDP +: {0}" -f $(if($Profile.UDPAdd){$Profile.UDPAdd}else{"—"}))
        Write-Host ("Raw:   {0}" -f $(if($Profile.RawExtraArgs){$Profile.RawExtraArgs}else{"—"}))
        Write-Host ""
        Write-Host "1. Base"
        Write-Host "2. TCP"
        Write-Host "3. UDP"
        Write-Host "4. Raw Extra Arguments"
        Write-Host "5. Итоговая команда"
        Write-Host "0. Назад"

        switch(Read-Host "Выбери") {
            "1" {$base=Select-UpstreamProfile;if($base){Save-UserProfile $Profile.Key $base $Profile.TCPAdd $Profile.UDPAdd $Profile.RawExtraArgs $Profile.Path | Out-Null}}
            "2" {$tcp=Read-Host "TCP";Save-UserProfile $Profile.Key $Profile.Base $tcp $Profile.UDPAdd $Profile.RawExtraArgs $Profile.Path | Out-Null}
            "3" {$udp=Read-Host "UDP";Save-UserProfile $Profile.Key $Profile.Base $Profile.TCPAdd $udp $Profile.RawExtraArgs $Profile.Path | Out-Null}
            "4" {$raw=Read-Host "Raw";Save-UserProfile $Profile.Key $Profile.Base $Profile.TCPAdd $Profile.UDPAdd $raw $Profile.Path | Out-Null}
            "5" {Write-Host "";Write-Host ('"{0}" {1}' -f $Winws,(Get-ProfileArguments $Profile.Key)) -ForegroundColor DarkGray;Read-Host "Enter" | Out-Null}
            "0" {return}
        }
    }
}

function Manage-UserProfiles {
    while($true) {
        Clear-Host
        Show-Header
        Write-Host ("Пользовательских профилей: {0}" -f @(Get-UserProfiles).Count) -ForegroundColor Cyan
        Write-Host "1. Создать"
        Write-Host "2. Изменить"
        Write-Host "3. Удалить"
        Write-Host "0. Назад"

        switch(Read-Host "Выбери") {
            "1" {Create-UserProfileInteractive;Read-Host "Enter" | Out-Null}
            "2" {$profile=Select-UserProfile;if($profile){Edit-UserProfile $profile}}
            "3" {
                $profile=Select-UserProfile
                if($profile -and (Read-Host "Для удаления введи ДА") -eq "ДА") {
                    Remove-Item -LiteralPath $profile.Path -Force
                }
            }
            "0" {return}
        }
    }
}

function Get-WfCoverage([string]$ProfileName,[string]$Protocol) {
    $args=[string](Get-ProfileArguments $ProfileName)
    $match=[regex]::Match($args,("--wf-"+$Protocol.ToLower()+"=([^\s]+)"))
    if($match.Success) {return $match.Groups[1].Value}
    return ""
}

function Get-NetworkProcessChoices {
    $ids=@()

    try {$ids += @(Get-NetTCPConnection -ErrorAction SilentlyContinue | Where-Object {$_.OwningProcess -gt 4} | Select-Object -ExpandProperty OwningProcess)} catch {}
    try {$ids += @(Get-NetUDPEndpoint -ErrorAction SilentlyContinue | Where-Object {$_.OwningProcess -gt 4} | Select-Object -ExpandProperty OwningProcess)} catch {}

    $rows=@()
    foreach($processId in @($ids | Sort-Object -Unique)) {
        try {
            $process=Get-Process -Id $processId -ErrorAction Stop
            if($process.ProcessName -notin @("System","Idle","winws")) {
                $rows += [pscustomobject]@{Name=$process.ProcessName;ProcessId=$processId}
            }
        } catch {}
    }

    return @($rows | Group-Object Name | Sort-Object Name | ForEach-Object {
        [pscustomobject]@{
            Name=$_.Name
            Display=("{0} [PID {1}]" -f $_.Name,(($_.Group.ProcessId | Sort-Object -Unique) -join ","))
        }
    })
}

function Save-PortScoutReport([string]$ProcessName,[int]$Duration,$TcpHits,$UdpHits) {
    Ensure-CustomDirs
    $runs=Join-Path $PortScoutDir "runs"
    New-Item -ItemType Directory -Force -Path $runs | Out-Null
    $stamp=Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $run=Join-Path $runs ($stamp+"-"+$ProcessName+".txt")
    $latest=Join-Path $PortScoutDir "latest.txt"

    $lines=@(
        "NetHawk Port Scout",
        "Процесс: $ProcessName",
        "Длительность: $Duration сек",
        "",
        "TCP remote ports:"
    )

    foreach($key in @($TcpHits.Keys | ForEach-Object {[int]$_} | Sort-Object)) {
        $lines += ("  {0,-6} seen {1}x" -f $key,$TcpHits[[string]$key])
    }

    $lines += ""
    $lines += "UDP local ports:"

    foreach($key in @($UdpHits.Keys | ForEach-Object {[int]$_} | Sort-Object)) {
        $lines += ("  {0,-6} seen {1}x" -f $key,$UdpHits[[string]$key])
    }

    $lines += ""
    $lines += "UDP показывает локальные endpoint-порты процесса."
    $lines += "winws на Windows фильтрует SrcPort и DstPort, поэтому их можно использовать в GameFilter."

    $lines | Set-Content -LiteralPath $run -Encoding UTF8
    $lines | Set-Content -LiteralPath $latest -Encoding UTF8
    return $run
}

function Add-PortsToUserProfile($Profile,[int[]]$TcpPorts,[int[]]$UdpPorts) {
    $tcp=Merge-PortSpecs @($Profile.TCPAdd,(($TcpPorts | Sort-Object -Unique) -join ","))
    $udp=Merge-PortSpecs @($Profile.UDPAdd,(($UdpPorts | Sort-Object -Unique) -join ","))
    Save-UserProfile $Profile.Key $Profile.Base $tcp $udp $Profile.RawExtraArgs $Profile.Path | Out-Null
}

function Invoke-PortScout {
    Clear-Host
    Show-Header
    Write-Host "Port Scout" -ForegroundColor Cyan

    $choices=@(Get-NetworkProcessChoices)
    if($choices.Count -eq 0) {throw "Нет процессов с активными сетевыми endpoint'ами."}

    for($i=0;$i -lt $choices.Count;$i++) {
        Write-Host ("  {0,2}. {1}" -f ($i+1),$choices[$i].Display)
    }

    $value=Read-Host "Процесс"
    $number=0
    if(-not[int]::TryParse($value,[ref]$number) -or $number -lt 1 -or $number -gt $choices.Count) {return}
    $processName=$choices[$number-1].Name

    $durationText=Read-Host "Секунд наблюдения [60]"
    $duration=60
    if($durationText) {
        $parsed=0
        if(-not[int]::TryParse($durationText,[ref]$parsed) -or $parsed -lt 5 -or $parsed -gt 300) {
            throw "Допустимо от 5 до 300 секунд."
        }
        $duration=$parsed
    }

    Write-Host ("[INFO] {0} сек. Пользуйся нужной функцией игры/приложения." -f $duration) -ForegroundColor Cyan
    $tcp=@{}
    $udp=@{}

    for($second=1;$second -le $duration;$second++) {
        $processIds=@(Get-Process -Name $processName -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)

        foreach($processId in $processIds) {
            foreach($connection in @(Get-NetTCPConnection -OwningProcess $processId -ErrorAction SilentlyContinue | Where-Object {$_.RemotePort -gt 0})) {
                $key=[string][int]$connection.RemotePort
                if($tcp.ContainsKey($key)) {$tcp[$key]++} else {$tcp[$key]=1}
            }

            foreach($endpoint in @(Get-NetUDPEndpoint -OwningProcess $processId -ErrorAction SilentlyContinue | Where-Object {$_.LocalPort -gt 0})) {
                $key=[string][int]$endpoint.LocalPort
                if($udp.ContainsKey($key)) {$udp[$key]++} else {$udp[$key]=1}
            }
        }

        if($second -eq 1 -or $second -eq $duration -or ($second % 5) -eq 0) {
            Write-Host ("[{0}/{1}] TCP {2} | UDP {3}" -f $second,$duration,$tcp.Count,$udp.Count) -ForegroundColor DarkGray
        }
        Start-Sleep -Seconds 1
    }

    $tcpPorts=@($tcp.Keys | ForEach-Object {[int]$_} | Sort-Object -Unique)
    $udpPorts=@($udp.Keys | ForEach-Object {[int]$_} | Sort-Object -Unique)
    $log=Save-PortScoutReport $processName $duration $tcp $udp

    Write-Host ""
    Write-Host ("TCP remote: {0}" -f $(if($tcpPorts.Count){$tcpPorts -join ","}else{"—"})) -ForegroundColor Cyan
    Write-Host ("UDP local:  {0}" -f $(if($udpPorts.Count){$udpPorts -join ","}else{"—"})) -ForegroundColor Cyan
    Write-Host ("Лог: {0}" -f $log) -ForegroundColor DarkGray

    if($tcpPorts.Count -eq 0 -and $udpPorts.Count -eq 0) {return}

    Write-Host ""
    Write-Host "1. Добавить глобально"
    Write-Host "2. Создать пользовательский профиль"
    Write-Host "3. Добавить в существующий профиль"
    Write-Host "0. Ничего не менять"

    switch(Read-Host "Выбери") {
        "1" {
            $global=Get-GlobalPorts
            $tcpAdd=@(Get-UncoveredPorts $tcpPorts (Merge-PortSpecs @($DefaultTcpCoverage,$global.TCP)))
            $udpAdd=@(Get-UncoveredPorts $udpPorts (Merge-PortSpecs @($DefaultUdpCoverage,$global.UDP)))
            $global.TCP=Merge-PortSpecs @($global.TCP,($tcpAdd -join ","))
            $global.UDP=Merge-PortSpecs @($global.UDP,($udpAdd -join ","))
            Save-GlobalPorts $global
            Write-Host "[OK] Глобальные порты обновлены." -ForegroundColor Green
        }
        "2" {
            $base=Select-UpstreamProfile
            if(-not $base) {return}
            $tcpAdd=@(Get-UncoveredPorts $tcpPorts (Get-WfCoverage $base "tcp"))
            $udpAdd=@(Get-UncoveredPorts $udpPorts (Get-WfCoverage $base "udp"))
            $name=Read-Host "Имя профиля"
            if($name) {
                Save-UserProfile $name $base ($tcpAdd -join ",") ($udpAdd -join ",") "" | Out-Null
                Write-Host "[OK] Профиль создан." -ForegroundColor Green
            }
        }
        "3" {
            $profile=Select-UserProfile
            if($profile) {
                $tcpAdd=@(Get-UncoveredPorts $tcpPorts (Get-WfCoverage $profile.Key "tcp"))
                $udpAdd=@(Get-UncoveredPorts $udpPorts (Get-WfCoverage $profile.Key "udp"))
                Add-PortsToUserProfile $profile $tcpAdd $udpAdd
                Write-Host "[OK] Профиль обновлён." -ForegroundColor Green
            }
        }
    }
}

function Start-SpecificElevatedAction([string]$ActionName,[string]$SelectedProfile="General") {
    $args='-NoLogo -NoProfile -ExecutionPolicy Bypass -File "{0}" -Action "{1}" -Profile "{2}" -KeepOpen' -f $EngineScript,$ActionName,$SelectedProfile
    Start-Process powershell.exe -Verb RunAs -ArgumentList $args | Out-Null
}

function Action-Ports { Configure-CustomPorts }
function Action-Profiles { Manage-UserProfiles }

function Action-PortScout {
    if(-not(Test-Administrator)) {
        Start-SpecificElevatedAction "PortScout"
        return
    }
    Invoke-PortScout
}

function Action-Status {
    Show-Header
    $settings=Get-V2Settings
    $ports=Get-GlobalPorts

    if(Get-Process winws -ErrorAction SilentlyContinue) {Write-Host "winws.exe: RUNNING"}
    else {Write-Host "winws.exe: STOPPED"}

    $service=Get-Service $ServiceName -ErrorAction SilentlyContinue
    if($service) {
        Write-Host ("Служба NetHawk: {0}" -f $service.Status)
        $profileValue=Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$ServiceName" -Name NetHawkProfile -ErrorAction SilentlyContinue
        if($profileValue) {Write-Host ("Профиль службы: {0}" -f $profileValue.NetHawkProfile)}
    } else {
        Write-Host "Служба NetHawk: НЕ УСТАНОВЛЕНА"
    }

    Write-Host ("Game Filter: {0}" -f $settings.GameFilter)
    Write-Host ("IPSet: {0}" -f $settings.IPSetMode)
    Write-Host ("Custom TCP: {0}" -f $(if($ports.TCP){$ports.TCP}else{"—"}))
    Write-Host ("Custom UDP: {0}" -f $(if($ports.UDP){$ports.UDP}else{"—"}))
    Write-Host ("Пользовательских профилей: {0}" -f @(Get-UserProfiles).Count)
}

function Action-Service {
    Require-Administrator

    while($true) {
        Clear-Host
        Show-Header
        Write-Host "1. Установить профиль как службу"
        Write-Host "2. Удалить службу"
        Write-Host "3. Статус"
        Write-Host "4. Game Filter"
        Write-Host "5. IPSet Filter"
        Write-Host "6. Discord fake"
        Write-Host "7. Game fake"
        Write-Host "8. Синхронизировать ресурсы"
        Write-Host "9. Обновить IPSet"
        Write-Host "10. Диагностика"
        Write-Host "11. Тестер профилей"
        Write-Host "12. Свои TCP/UDP"
        Write-Host "13. Пользовательские профили"
        Write-Host "14. Port Scout"
        Write-Host "0. Выход"

        switch(Read-Host "Выбери") {
            "1" {$profile=Select-V2Profile;if($profile){Install-V2Service $profile};Read-Host "Enter" | Out-Null}
            "2" {Remove-V2Service;Read-Host "Enter" | Out-Null}
            "3" {Action-Status;Read-Host "Enter" | Out-Null}
            "4" {Configure-V2GameFilter}
            "5" {Configure-V2IPSet}
            "6" {Configure-V2Fake "Discord"}
            "7" {Configure-V2Fake "Game"}
            "8" {Sync-V2Resources;Read-Host "Enter" | Out-Null}
            "9" {Update-V2IPSet;Read-Host "Enter" | Out-Null}
            "10" {Action-Diagnostics;Read-Host "Enter" | Out-Null}
            "11" {Action-Test;Read-Host "Enter" | Out-Null}
            "12" {Configure-CustomPorts}
            "13" {Manage-UserProfiles}
            "14" {Invoke-PortScout;Read-Host "Enter" | Out-Null}
            "0" {return}
        }
    }
}

function Action-SelfTest {
    Show-Header
    Assert-Runtime
    Ensure-CustomDirs

    $hadPorts=Test-Path $PortsPath
    $backup=if($hadPorts){Get-Content $PortsPath -Raw}else{$null}
    $tempName="__SELFTEST_"+[Guid]::NewGuid().ToString("N")
    $tempPath=Join-Path $UserProfilesDir ($tempName+".json")
    $count=0

    try {
        [pscustomobject]@{TCP="45678";UDP="45679"} | ConvertTo-Json | Set-Content $PortsPath -Encoding UTF8

        foreach($item in Get-ProfileCatalogV2) {
            $args=[string](Get-ProfileArguments $item.Key)
            if($args -match "%(BIN|LISTS|GameFilter)") {throw "$($item.Key): unresolved variable"}
            if($args -notmatch '45678' -or $args -notmatch '45679') {throw "$($item.Key): custom ports missing"}

            foreach($match in [regex]::Matches($args,'"([^"]+\.(?:bin|txt))"')) {
                if(-not(Test-Path $match.Groups[1].Value)) {throw "$($item.Key): missing resource"}
            }

            $count++
            Write-Host ("[OK] {0}" -f $item.Key)
        }

        Save-UserProfile $tempName "General" "45680" "45681" "" | Out-Null
        $customArgs=[string](Get-ProfileArguments $tempName)
        if($customArgs -notmatch '45680' -or $customArgs -notmatch '45681') {throw "user override failed"}
        Write-Host "[OK] User profile override"
    }
    finally {
        Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
        if($hadPorts) {[IO.File]::WriteAllText($PortsPath,$backup,[Text.Encoding]::UTF8)}
        else {Remove-Item $PortsPath -Force -ErrorAction SilentlyContinue}
    }

    Write-Host ("[OK] SelfTest profiles={0}" -f $count)
}

function Action-V2Menu {
    while($true) {
        Clear-Host
        Show-Header
        Write-Host "1. Запустить профиль"
        Write-Host "2. Свои TCP/UDP"
        Write-Host "3. Пользовательские профили"
        Write-Host "4. Port Scout"
        Write-Host "5. Тестер профилей"
        Write-Host "6. Менеджер службы"
        Write-Host "7. Статус"
        Write-Host "0. Выход"

        switch(Read-Host "Выбери") {
            "1" {
                $profile=Select-V2Profile
                if($profile) {
                    if(Test-Administrator) {Start-Profile $profile;Write-Host "[OK] Запущено." -ForegroundColor Green;Read-Host "Enter" | Out-Null}
                    else {Start-SpecificElevatedAction "Run" $profile;return}
                }
            }
            "2" {Configure-CustomPorts}
            "3" {Manage-UserProfiles}
            "4" {if(Test-Administrator){Invoke-PortScout;Read-Host "Enter" | Out-Null}else{Start-SpecificElevatedAction "PortScout";return}}
            "5" {if(Test-Administrator){Action-Test;Read-Host "Enter" | Out-Null}else{Start-SpecificElevatedAction "Test";return}}
            "6" {if(Test-Administrator){Action-Service}else{Start-SpecificElevatedAction "Service";return}}
            "7" {Action-Status;Read-Host "Enter" | Out-Null}
            "0" {return}
        }
    }
}
