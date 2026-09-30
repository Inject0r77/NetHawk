param(
    [ValidateSet("Menu","Run","Test","Service","Diagnostics","Status","Stop","Bootstrap","Sync","SelfTest","UpdateIPSet","Ports","Profiles","PortScout")]
    [string]$Action = "Status",

    [string]$Profile = "General",

    [switch]$KeepOpen
)

$ErrorActionPreference = "Stop"
$Version = "0.3.0-dev1"

$Root = Split-Path -Parent $PSScriptRoot
$Bin = Join-Path $Root "bin"
$Lists = Join-Path $Root "lists"
$Winws = Join-Path $Bin "winws.exe"
$ServiceName = "NetHawk"
$PreviousServiceName = "NetLayer"
$LegacyServiceName = "DPIBypass"
$Profiles = Join-Path $Root "profiles"
$Config = Join-Path $Root "config"
$SettingsPath = Join-Path $Config "settings.json"
$FlowsealCommit = "249a70424aae2676f99c5363e21073ed89873eda"
$FlowsealRepo = "Flowseal/zapret-discord-youtube"

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Restart-Elevated {
    $argLine = '-NoLogo -NoProfile -ExecutionPolicy Bypass -File "{0}" -Action "{1}" -Profile "{2}"' -f $PSCommandPath,$Action,$Profile
    if ($KeepOpen) {
        $argLine += ' -KeepOpen'
    }
    Start-Process -FilePath "powershell.exe" -Verb RunAs -ArgumentList $argLine | Out-Null
    exit 0
}

function Require-Administrator {
    if (-not (Test-Administrator)) {
        Write-Host "[INFO] Запрашиваю права администратора..."
        Restart-Elevated
    }
}

function Assert-Runtime {
    $required = @(
        (Join-Path $Bin "winws.exe"),
        (Join-Path $Bin "WinDivert.dll"),
        (Join-Path $Bin "WinDivert64.sys")
    )

    foreach ($file in $required) {
        if (-not (Test-Path -LiteralPath $file)) {
            throw "Не найден runtime-файл: $file"
        }
    }
}

function Quote-PathArg([string]$Name,[string]$Path) {
    return ('--{0}="{1}"' -f $Name,$Path)
}

function Get-ProfileArguments([string]$Name) {
    $general = Join-Path $Lists "list-general.txt"
    $user = Join-Path $Lists "list-general-user.txt"
    $exclude = Join-Path $Lists "list-exclude.txt"
    $excludeUser = Join-Path $Lists "list-exclude-user.txt"

    $base = @(
        "--wf-tcp=80,443,2053,2083,2087,2096,8443",
        "--wf-udp=443,19294-19344,50000-50100"
    )

    $hostArgs = @(
        (Quote-PathArg "hostlist" $general),
        (Quote-PathArg "hostlist" $user),
        (Quote-PathArg "hostlist-exclude" $exclude),
        (Quote-PathArg "hostlist-exclude" $excludeUser)
    )

    switch ($Name) {
        "General" {
            return $base + @(
                "--filter-udp=443"
            ) + $hostArgs + @(
                "--dpi-desync=fake",
                "--dpi-desync-repeats=6",
                "--new",
                "--filter-tcp=80,443"
            ) + $hostArgs + @(
                "--dpi-desync=multisplit",
                "--dpi-desync-split-pos=1"
            )
        }

        "ALT1" {
            return $base + @(
                "--filter-udp=443"
            ) + $hostArgs + @(
                "--dpi-desync=fake",
                "--dpi-desync-repeats=8",
                "--new",
                "--filter-tcp=80,443"
            ) + $hostArgs + @(
                "--dpi-desync=fake,fakedsplit",
                "--dpi-desync-repeats=6",
                "--dpi-desync-fooling=md5sig"
            )
        }

        "ALT2" {
            return $base + @(
                "--filter-udp=443",
                (Quote-PathArg "hostlist" $general),
                (Quote-PathArg "hostlist" $user),
                "--dpi-desync=fake",
                "--dpi-desync-repeats=11",
                "--new",
                "--filter-tcp=443",
                (Quote-PathArg "hostlist" $general),
                (Quote-PathArg "hostlist" $user),
                "--dpi-desync=fake,multidisorder",
                "--dpi-desync-split-pos=1,midsld",
                "--dpi-desync-repeats=8",
                "--dpi-desync-fooling=md5sig",
                "--new",
                "--filter-tcp=80",
                (Quote-PathArg "hostlist" $general),
                (Quote-PathArg "hostlist" $user),
                "--dpi-desync=fake,fakedsplit"
            )
        }

        "EXP" {
            return $base + @(
                "--filter-udp=443",
                (Quote-PathArg "hostlist" $general),
                (Quote-PathArg "hostlist" $user),
                "--dpi-desync=fake",
                "--dpi-desync-repeats=12",
                "--new",
                "--filter-tcp=443",
                (Quote-PathArg "hostlist" $general),
                (Quote-PathArg "hostlist" $user),
                "--dpi-desync=fake,multisplit",
                "--dpi-desync-split-pos=1,midsld",
                "--dpi-desync-repeats=10",
                "--dpi-desync-fooling=badseq,md5sig",
                "--new",
                "--filter-tcp=80",
                (Quote-PathArg "hostlist" $general),
                (Quote-PathArg "hostlist" $user),
                "--dpi-desync=fake,fakedsplit",
                "--dpi-desync-repeats=4"
            )
        }
    }
}

function Stop-Winws {
    Get-Process -Name "winws" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

function Test-ServiceRunning {
    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    return ($null -ne $service -and $service.Status -eq "Running")
}

function Start-Profile([string]$Name,[switch]$IgnoreServiceGuard) {
    Assert-Runtime

    if (-not $IgnoreServiceGuard -and (Test-ServiceRunning)) {
        throw "Служба $ServiceName уже запущена. Сначала останови её через service.bat или stop.bat."
    }

    Stop-Winws
    $args = Get-ProfileArguments $Name
    $argLine = $args -join " "

    Start-Process -FilePath $Winws -ArgumentList $argLine -WindowStyle Minimized | Out-Null
    Start-Sleep -Milliseconds 500

    $proc = Get-Process -Name "winws" -ErrorAction SilentlyContinue
    if ($null -eq $proc) {
        throw "winws.exe не запустился."
    }
}

function Test-Url([string]$Url) {
    $curl = Get-Command "curl.exe" -ErrorAction SilentlyContinue
    if ($null -eq $curl) {
        throw "В системе не найден curl.exe."
    }

    $p = Start-Process -FilePath $curl.Source -ArgumentList @(
        "-L","-sS","-o","NUL","--max-time","10",$Url
    ) -WindowStyle Hidden -Wait -PassThru

    return ($p.ExitCode -eq 0)
}

function Show-Header {
    Write-Host ""
    Write-Host "============================================================"
    Write-Host "  NetHawk $Version"
    Write-Host "  Основано на Flowseal/zapret-discord-youtube"
    Write-Host "  Движок: bol-van/zapret (winws) + WinDivert"
    Write-Host "============================================================"
    Write-Host ""
}

function Action-Run {
    Require-Administrator
    Show-Header
    Write-Host "[INFO] Профиль: $Profile"
    Start-Profile $Profile
    Write-Host "[OK] NetHawk запущен."
}

function Action-Stop {
    Require-Administrator
    foreach($name in @($ServiceName,$PreviousServiceName,$LegacyServiceName)) {
        $service = Get-Service -Name $name -ErrorAction SilentlyContinue
        if ($null -ne $service -and $service.Status -ne "Stopped") {
            Stop-Service -Name $name -Force -ErrorAction SilentlyContinue
        }
    }
    Stop-Winws
    Write-Host "[OK] NetHawk остановлен."
}

function Action-Status {
    Show-Header

    $proc = Get-Process -Name "winws" -ErrorAction SilentlyContinue
    if ($null -ne $proc) {
        Write-Host "winws.exe: ЗАПУЩЕН"
    } else {
        Write-Host "winws.exe: НЕ ЗАПУЩЕН"
    }

    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($null -eq $service) {
        Write-Host "Служба: НЕ УСТАНОВЛЕНА"
    } else {
        Write-Host ("Служба: {0}" -f $service.Status)
        $profileValue = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$ServiceName" -Name "NetHawkProfile" -ErrorAction SilentlyContinue
        if ($null -ne $profileValue) {
            Write-Host ("Профиль службы: {0}" -f $profileValue.NetHawkProfile)
        }
    }
}

function Action-Test {
    Require-Administrator
    Assert-Runtime
    Show-Header

    $serviceWasRunning = Test-ServiceRunning
    if ($serviceWasRunning) {
        Write-Host "[INFO] Временно останавливаю службу $ServiceName..."
        Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
    }

    Stop-Winws

    $logDir = Join-Path $Root "logs"
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    $log = Join-Path $logDir "strategy-test.log"
    "NetHawk $Version strategy test" | Set-Content -LiteralPath $log -Encoding UTF8

    $bestScore = -1
    $bestProfiles = @()

    foreach ($name in @("General","ALT1","ALT2","EXP")) {
        Write-Host "================================================"
        Write-Host "Тест: $name"
        Write-Host "================================================"

        Start-Profile $name -IgnoreServiceGuard
        Start-Sleep -Seconds 3

        $score = 0
        $checks = @(
            @{ Label="YouTube HTTPS"; Url="https://www.youtube.com/" },
            @{ Label="Discord HTTPS"; Url="https://discord.com/" },
            @{ Label="Discord API"; Url="https://discord.com/api/v10/gateway" }
        )

        Add-Content -LiteralPath $log -Value ""
        Add-Content -LiteralPath $log -Value "[$name]"

        foreach ($check in $checks) {
            $ok = Test-Url $check.Url
            if ($ok) {
                Write-Host ("{0}: OK" -f $check.Label)
                Add-Content -LiteralPath $log -Value ("{0}: OK" -f $check.Label)
                $score++
            } else {
                Write-Host ("{0}: FAIL" -f $check.Label)
                Add-Content -LiteralPath $log -Value ("{0}: FAIL" -f $check.Label)
            }
        }

        Write-Host ("Результат: {0}/3" -f $score)
        Add-Content -LiteralPath $log -Value ("Score: {0}/3" -f $score)

        if ($score -gt $bestScore) {
            $bestScore = $score
            $bestProfiles = @($name)
        } elseif ($score -eq $bestScore) {
            $bestProfiles += $name
        }

        Stop-Winws
        Start-Sleep -Seconds 1
    }

    if ($serviceWasRunning) {
        Write-Host "[INFO] Возвращаю службу $ServiceName..."
        Start-Service -Name $ServiceName -ErrorAction SilentlyContinue
    }

    Write-Host ""
    Write-Host "================================================"
    Write-Host "Итог"
    Write-Host "================================================"
    Write-Host ("Лучший HTTPS-результат: {0}/3" -f $bestScore)
    Write-Host ("Профили: {0}" -f ($bestProfiles -join ", "))
    Write-Host ("Лог: {0}" -f $log)
    Write-Host ""
    Write-Host "Discord Voice/UDP и реальная работа QUIC этим тестом пока не подтверждаются."
}

function Action-Service {
    Require-Administrator
    Assert-Runtime

    while ($true) {
        Clear-Host
        Show-Header
        Write-Host "1. Установить профиль как службу"
        Write-Host "2. Удалить службу"
        Write-Host "3. Запустить службу"
        Write-Host "4. Остановить службу"
        Write-Host "5. Статус"
        Write-Host "0. Выход"
        Write-Host ""

        $choice = Read-Host "Выбери пункт"

        switch ($choice) {
            "1" {
                Write-Host ""
                Write-Host "1. General"
                Write-Host "2. ALT1"
                Write-Host "3. ALT2"
                Write-Host "4. EXP"
                $pc = Read-Host "Профиль"

                $selected = switch ($pc) {
                    "1" { "General" }
                    "2" { "ALT1" }
                    "3" { "ALT2" }
                    "4" { "EXP" }
                    default { $null }
                }

                if ($null -eq $selected) {
                    Write-Host "[ОШИБКА] Неверный профиль."
                    Read-Host "Enter"
                    continue
                }

                $existing = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
                if ($null -ne $existing) {
                    Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
                    & sc.exe delete $ServiceName | Out-Null
                    Start-Sleep -Seconds 1
                }

                $args = Get-ProfileArguments $selected
                $binaryPath = '"' + $Winws + '" ' + ($args -join " ")
                New-Service -Name $ServiceName -BinaryPathName $binaryPath -DisplayName "NetHawk" -StartupType Automatic | Out-Null
                New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$ServiceName" -Name "NetHawkProfile" -Value $selected -PropertyType String -Force | Out-Null
                Start-Service -Name $ServiceName
                Write-Host "[OK] Служба установлена. Профиль: $selected"
                Read-Host "Enter"
            }

            "2" {
                $existing = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
                if ($null -ne $existing) {
                    Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
                    & sc.exe delete $ServiceName | Out-Null
                    Start-Sleep -Seconds 1
                }
                Stop-Winws
                Write-Host "[OK] Служба удалена."
                Read-Host "Enter"
            }

            "3" {
                Start-Service -Name $ServiceName -ErrorAction Continue
                Read-Host "Enter"
            }

            "4" {
                Stop-Service -Name $ServiceName -Force -ErrorAction Continue
                Stop-Winws
                Read-Host "Enter"
            }

            "5" {
                Action-Status
                Read-Host "Enter"
            }

            "0" { return }
        }
    }
}

function Action-Diagnostics {
    Show-Header
    Write-Host "Диагностика NetHawk"
    Write-Host ""

    try {
        Assert-Runtime
        Write-Host "[OK] Runtime winws/WinDivert найден."
    } catch {
        Write-Host ("[X] {0}" -f $_.Exception.Message)
    }

    $bfe = Get-Service -Name "BFE" -ErrorAction SilentlyContinue
    if ($null -ne $bfe -and $bfe.Status -eq "Running") {
        Write-Host "[OK] Base Filtering Engine работает."
    } else {
        Write-Host "[X] Base Filtering Engine не запущен."
    }

    $proxy = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -ErrorAction SilentlyContinue
    if ($null -ne $proxy -and $proxy.ProxyEnable -eq 1) {
        Write-Host ("[!] В Windows включён proxy: {0}" -f $proxy.ProxyServer)
    } else {
        Write-Host "[OK] Системный proxy не включён."
    }

    foreach ($svcName in @("GoodbyeDPI","zapret","discordfix_zapret","winws1","winws2")) {
        $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
        if ($null -ne $svc) {
            Write-Host ("[!] Потенциально конфликтующая служба: {0}" -f $svcName)
        }
    }

    $hosts = Join-Path $env:SystemRoot "System32\drivers\etc\hosts"
    if (Test-Path -LiteralPath $hosts) {
        $hostsText = Get-Content -LiteralPath $hosts -ErrorAction SilentlyContinue
        if ($hostsText -match "youtube\.com|youtu\.be|discord\.com|discord\.gg") {
            Write-Host "[!] В hosts есть записи YouTube/Discord."
        } else {
            Write-Host "[OK] Подозрительных записей YouTube/Discord в hosts не найдено."
        }
    }

    foreach ($domain in @("youtube.com","discord.com")) {
        try {
            Resolve-DnsName $domain -ErrorAction Stop | Out-Null
            Write-Host ("[OK] DNS: {0}" -f $domain)
        } catch {
            Write-Host ("[X] DNS: {0}" -f $domain)
        }
    }

    foreach ($target in @(
        @{ Label="YouTube"; Url="https://www.youtube.com/" },
        @{ Label="Discord"; Url="https://discord.com/" }
    )) {
        try {
            if (Test-Url $target.Url) {
                Write-Host ("[OK] HTTPS: {0}" -f $target.Label)
            } else {
                Write-Host ("[!] HTTPS: {0}" -f $target.Label)
            }
        } catch {
            Write-Host ("[!] HTTPS: {0} - {1}" -f $target.Label,$_.Exception.Message)
        }
    }
}

function Action-Bootstrap {
    Require-Administrator

    $tmp = Join-Path $env:TEMP ("dpibypass_runtime_" + [Guid]::NewGuid().ToString("N"))
    $zip = Join-Path $tmp "bundle.zip"
    $extract = Join-Path $tmp "extract"

    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    New-Item -ItemType Directory -Force -Path $Bin | Out-Null

    try {
        Write-Host "[1/3] Скачиваю официальный bol-van/zapret-win-bundle..."
        Invoke-WebRequest -UseBasicParsing -Uri "https://github.com/bol-van/zapret-win-bundle/archive/refs/heads/master.zip" -OutFile $zip

        Write-Host "[2/3] Распаковываю..."
        Expand-Archive -LiteralPath $zip -DestinationPath $extract -Force

        $runtime = Join-Path $extract "zapret-win-bundle-master\zapret-winws"

        Write-Host "[3/3] Копирую runtime..."
        foreach ($name in @("winws.exe","WinDivert.dll","WinDivert64.sys","cygwin1.dll")) {
            Copy-Item -LiteralPath (Join-Path $runtime $name) -Destination (Join-Path $Bin $name) -Force
        }

        Write-Host "[OK] Runtime установлен."
    } finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Action-SelfTest {
    Show-Header
    Write-Host "Проверка генератора профилей..."
    Write-Host ""

    foreach ($name in @("General","ALT1","ALT2","EXP")) {
        $profileArgs = @(Get-ProfileArguments $name)

        if ($profileArgs.Count -eq 0) {
            throw "Профиль $name не вернул аргументы."
        }

        if (-not ($profileArgs -contains "--wf-tcp=80,443,2053,2083,2087,2096,8443")) {
            throw "Профиль $name не содержит базовый TCP-фильтр."
        }

        if (-not ($profileArgs -contains "--wf-udp=443,19294-19344,50000-50100")) {
            throw "Профиль $name не содержит базовый UDP-фильтр."
        }

        Write-Host ("[OK] {0}: {1} аргументов" -f $name,$profileArgs.Count)
    }

    Write-Host ""
    Write-Host "[OK] Self-test завершён."
}


function Get-ProfileCatalogV2 {
    @(
        [pscustomobject]@{Key="General";Source="general.bat";Launcher="general.bat"},
        [pscustomobject]@{Key="ALT1";Source="general (ALT).bat";Launcher="general (ALT1).bat"},
        [pscustomobject]@{Key="ALT2";Source="general (ALT2).bat";Launcher="general (ALT2).bat"},
        [pscustomobject]@{Key="ALT3";Source="general (ALT3).bat";Launcher="general (ALT3).bat"},
        [pscustomobject]@{Key="ALT4";Source="general (ALT4).bat";Launcher="general (ALT4).bat"},
        [pscustomobject]@{Key="ALT5";Source="general (ALT5).bat";Launcher="general (ALT5).bat"},
        [pscustomobject]@{Key="ALT6";Source="general (ALT6).bat";Launcher="general (ALT6).bat"},
        [pscustomobject]@{Key="ALT7";Source="general (ALT7).bat";Launcher="general (ALT7).bat"},
        [pscustomobject]@{Key="ALT8";Source="general (ALT8).bat";Launcher="general (ALT8).bat"},
        [pscustomobject]@{Key="ALT9";Source="general (ALT9).bat";Launcher="general (ALT9).bat"},
        [pscustomobject]@{Key="ALT10";Source="general (ALT10).bat";Launcher="general (ALT10).bat"},
        [pscustomobject]@{Key="ALT11";Source="general (ALT11).bat";Launcher="general (ALT11).bat"},
        [pscustomobject]@{Key="ALT12";Source="general (ALT12).bat";Launcher="general (ALT12).bat"},
        [pscustomobject]@{Key="EXP";Source="general (EXP).bat";Launcher="general (EXP).bat"},
        [pscustomobject]@{Key="FAKE_TLS_AUTO";Source="general (FAKE TLS AUTO).bat";Launcher="general (FAKE TLS AUTO).bat"},
        [pscustomobject]@{Key="FAKE_TLS_AUTO_ALT1";Source="general (FAKE TLS AUTO ALT).bat";Launcher="general (FAKE TLS AUTO ALT1).bat"},
        [pscustomobject]@{Key="FAKE_TLS_AUTO_ALT2";Source="general (FAKE TLS AUTO ALT2).bat";Launcher="general (FAKE TLS AUTO ALT2).bat"},
        [pscustomobject]@{Key="FAKE_TLS_AUTO_ALT3";Source="general (FAKE TLS AUTO ALT3).bat";Launcher="general (FAKE TLS AUTO ALT3).bat"},
        [pscustomobject]@{Key="SIMPLE_FAKE";Source="general (SIMPLE FAKE).bat";Launcher="general (SIMPLE FAKE).bat"},
        [pscustomobject]@{Key="SIMPLE_FAKE_ALT1";Source="general (SIMPLE FAKE ALT).bat";Launcher="general (SIMPLE FAKE ALT1).bat"},
        [pscustomobject]@{Key="SIMPLE_FAKE_ALT2";Source="general (SIMPLE FAKE ALT2).bat";Launcher="general (SIMPLE FAKE ALT2).bat"}
    )
}

function Ensure-V2Directories {
    foreach($p in @($Bin,$Lists,$Profiles,$Config)) {
        if(-not (Test-Path -LiteralPath $p)) {
            New-Item -ItemType Directory -Force -Path $p | Out-Null
        }
    }
}

function Get-V2Settings {
    Ensure-V2Directories
    $s=[ordered]@{GameFilter="off";IPSetMode="loaded";DiscordFake="ACTIVE_DISCORD_UDP.bin";GameFake="ACTIVE_GAME_UDP.bin"}
    if(Test-Path -LiteralPath $SettingsPath) {
        try {
            $j=Get-Content -LiteralPath $SettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach($k in @("GameFilter","IPSetMode","DiscordFake","GameFake")) {
                if($null -ne $j.$k -and [string]$j.$k -ne "") {
                    $s[$k]=[string]$j.$k
                }
            }
        } catch {}
    }
    $s
}

function Save-V2Settings($s) {
    Ensure-V2Directories
    [pscustomobject]$s | ConvertTo-Json | Set-Content -LiteralPath $SettingsPath -Encoding UTF8
}

function Ensure-V2UserFiles {
    Ensure-V2Directories
    $pairs=@(
        @("list-general-user.txt",@("domain.example.abc")),
        @("list-exclude-user.txt",@("domain.example.abc")),
        @("ipset-exclude-user.txt",@("203.0.113.113/32")),
        @("ipset-none.txt",@("203.0.113.113/32"))
    )
    foreach($pair in $pairs) {
        $p=Join-Path $Lists $pair[0]
        if(-not(Test-Path -LiteralPath $p)) {
            [IO.File]::WriteAllLines($p,[string[]]$pair[1],[Text.Encoding]::ASCII)
        }
    }
    [IO.File]::WriteAllText((Join-Path $Lists "ipset-any.txt"),"")
}

function Get-FlowsealRawUrl([string]$RelativePath,[string]$Commit=$FlowsealCommit) {
    $encoded=(($RelativePath -split "/") | ForEach-Object {[Uri]::EscapeDataString($_)}) -join "/"
    "https://raw.githubusercontent.com/$FlowsealRepo/$Commit/$encoded"
}

function Download-FlowsealFile([string]$RelativePath,[string]$Destination,[string]$Commit=$FlowsealCommit) {
    $parent=Split-Path -Parent $Destination
    if($parent -and -not(Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    Invoke-WebRequest -UseBasicParsing -Uri (Get-FlowsealRawUrl $RelativePath $Commit) -OutFile $Destination -TimeoutSec 30
}

function Write-V2Launcher($item) {
    $path=Join-Path $Root $item.Launcher
    $lines=@(
        "@echo off",
        "setlocal",
        'cd /d "%~dp0"',
        ('powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\NetHawk.ps1" -Action Run -Profile "{0}"' -f $item.Key),
        "if errorlevel 1 pause",
        ""
    )
    $crlf=([string][char]13)+([string][char]10)
    [IO.File]::WriteAllText($path,($lines -join $crlf),[Text.Encoding]::ASCII)
}

function Sync-V2Resources {
    Show-Header
    Ensure-V2Directories
    Ensure-V2UserFiles

    Write-Host "[1/5] Профили..."
    foreach($item in Get-ProfileCatalogV2) {
        Download-FlowsealFile $item.Source (Join-Path $Profiles ($item.Key+".profile"))
        Write-V2Launcher $item
    }

    Write-Host "[2/5] Списки..."
    $map=@{
        "lists/list-general.txt"="list-general.txt"
        "lists/list-exclude.txt"="list-exclude.txt"
        "lists/list-google.txt"="list-google.txt"
        "lists/ipset-exclude.txt"="ipset-exclude.txt"
        ".service/ipset-service.txt"="ipset-all.txt"
    }
    foreach($src in $map.Keys) {
        Download-FlowsealFile $src (Join-Path $Lists $map[$src])
    }
    Copy-Item (Join-Path $Lists "ipset-all.txt") (Join-Path $Lists "ipset-all.txt.backup") -Force

    Write-Host "[3/5] winws и WinDivert..."
    foreach($n in @("winws.exe","WinDivert.dll","WinDivert64.sys","cygwin1.dll")) {
        Download-FlowsealFile ("bin/"+$n) (Join-Path $Bin $n)
    }

    Write-Host "[4/5] Fake payloads..."
    $bins=@(
        "ACTIVE_DISCORD_UDP.bin","ACTIVE_GAME_UDP.bin","quic_initial_4pda_to.bin",
        "quic_initial_5ka_ru.bin","quic_initial_rutube_ru.bin","quic_initial_steamcommunity_com.bin",
        "quic_initial_tencent_com.bin","quic_initial_www_google_com.bin","stun.bin","stun2.bin",
        "tls_clienthello_4pda_to.bin","tls_clienthello_5ka_ru.bin","tls_clienthello_max_ru.bin",
        "tls_clienthello_sochi_park.bin","tls_clienthello_www_google_com.bin","tls_clienthello_www_sferum_ru.bin"
    )
    foreach($n in $bins) {
        Download-FlowsealFile ("bin/"+$n) (Join-Path $Bin $n)
    }
    Copy-Item (Join-Path $Bin "ACTIVE_GAME_UDP.bin") (Join-Path $Bin "quic_initial_dbankcloud_ru.bin") -Force

    Write-Host "[5/5] Пользовательские файлы..."
    Ensure-V2UserFiles
    Write-Host "[OK] Синхронизация завершена."
}

function Assert-Runtime {
    $required=@(
        (Join-Path $Bin "winws.exe"),(Join-Path $Bin "WinDivert.dll"),(Join-Path $Bin "WinDivert64.sys"),
        (Join-Path $Lists "list-general.txt"),(Join-Path $Lists "list-google.txt"),
        (Join-Path $Lists "list-exclude.txt"),(Join-Path $Lists "ipset-all.txt"),(Join-Path $Lists "ipset-exclude.txt")
    )
    foreach($p in $required) {
        if(-not(Test-Path -LiteralPath $p)) {
            throw "Не найден ресурс: $p. Запусти tools\sync-resources.bat."
        }
    }
    foreach($item in Get-ProfileCatalogV2) {
        $p=Join-Path $Profiles ($item.Key+".profile")
        if(-not(Test-Path -LiteralPath $p)) {
            throw "Не найден профиль $($item.Key). Запусти tools\sync-resources.bat."
        }
    }
}

function Get-V2GamePorts($s) {
    switch($s.GameFilter) {
        "all" {[pscustomobject]@{TCP="1024-65535";UDP="1024-65535";Both="1024-65535"}}
        "tcp" {[pscustomobject]@{TCP="1024-65535";UDP="12";Both="1024-65535"}}
        "udp" {[pscustomobject]@{TCP="12";UDP="1024-65535";Both="1024-65535"}}
        default {[pscustomobject]@{TCP="12";UDP="12";Both="12"}}
    }
}

function Get-V2IPSetPath($s) {
    switch($s.IPSetMode) {
        "none" {Join-Path $Lists "ipset-none.txt"}
        "any" {Join-Path $Lists "ipset-any.txt"}
        default {Join-Path $Lists "ipset-all.txt"}
    }
}

function Get-ProfileArguments([string]$Name) {
    Ensure-V2UserFiles
    Assert-Runtime

    $info=Get-ProfileCatalogV2 | Where-Object {$_.Key -eq $Name} | Select-Object -First 1
    if($null -eq $info) {
        throw "Неизвестный профиль: $Name"
    }

    $path=Join-Path $Profiles ($Name+".profile")
    $lines=Get-Content -LiteralPath $path
    $start=-1
    for($i=0;$i -lt $lines.Count;$i++) {
        if($lines[$i] -match "winws\.exe") {
            $start=$i
            break
        }
    }
    if($start -lt 0) {
        throw ("{0}: winws.exe не найден в профиле" -f $Name)
    }

    $parts=New-Object System.Collections.Generic.List[string]
    $rx=New-Object Text.RegularExpressions.Regex('^.*?winws\.exe"?\s*',[Text.RegularExpressions.RegexOptions]::IgnoreCase)
    for($i=$start;$i -lt $lines.Count;$i++) {
        $line=[string]$lines[$i]
        if($i -eq $start) {
            $line=$rx.Replace($line,"")
        }
        $t=$line.Trim()
        $continued=$t.EndsWith("^")
        if($continued) {
            $t=$t.Substring(0,$t.Length-1).Trim()
        }
        if($t) {
            $parts.Add($t)
        }
        if(-not $continued) {
            break
        }
    }

    $a=$parts -join " "
    $s=Get-V2Settings
    $g=Get-V2GamePorts $s
    $ip=Get-V2IPSetPath $s
    $discordFake=Join-Path $Bin $s.DiscordFake
    $gameFake=Join-Path $Bin $s.GameFake
    if(-not(Test-Path -LiteralPath $discordFake)) {
        $discordFake=Join-Path $Bin "ACTIVE_DISCORD_UDP.bin"
    }
    if(-not(Test-Path -LiteralPath $gameFake)) {
        $gameFake=Join-Path $Bin "ACTIVE_GAME_UDP.bin"
    }

    $a=$a.Replace('"%LISTS%ipset-all.txt"',('"'+$ip+'"'))
    $a=$a.Replace('"%BIN%ACTIVE_DISCORD_UDP.bin"',('"'+$discordFake+'"'))
    $a=$a.Replace('"%BIN%ACTIVE_GAME_UDP.bin"',('"'+$gameFake+'"'))
    $a=$a.Replace("%GameFilterTCP%",$g.TCP)
    $a=$a.Replace("%GameFilterUDP%",$g.UDP)
    $a=$a.Replace("%GameFilter%",$g.Both)
    $a=$a.Replace("%BIN%",($Bin.TrimEnd("\")+"\"))
    $a=$a.Replace("%LISTS%",($Lists.TrimEnd("\")+"\"))

    return $a
}

function Start-Profile([string]$Name,[switch]$IgnoreServiceGuard) {
    Assert-Runtime
    if(-not $IgnoreServiceGuard -and (Test-ServiceRunning)) {
        throw "Служба $ServiceName уже запущена."
    }
    Stop-Winws
    try {
        & netsh interface tcp set global timestamps=enabled | Out-Null
    } catch {}
    $argLine=Get-ProfileArguments $Name
    Start-Process -FilePath $Winws -ArgumentList $argLine -WindowStyle Minimized | Out-Null
    Start-Sleep -Milliseconds 700
    if($null -eq (Get-Process -Name "winws" -ErrorAction SilentlyContinue)) {
        throw "winws.exe не запустился."
    }
}

function Select-V2Profile {
    $catalog=@(Get-ProfileCatalogV2)
    Write-Host ""
    for($i=0;$i -lt $catalog.Count;$i++) {
        Write-Host ("  {0,2}. {1}" -f ($i+1),$catalog[$i].Key)
    }
    Write-Host "   0. Назад"
    $value=Read-Host "Профиль"
    $number=0
    if(-not[int]::TryParse($value,[ref]$number)) {
        return $null
    }
    if($number -lt 1 -or $number -gt $catalog.Count) {
        return $null
    }
    return $catalog[$number-1].Key
}

function Configure-V2GameFilter {
    $s=Get-V2Settings
    Write-Host "0 Выкл | 1 TCP+UDP | 2 TCP | 3 UDP"
    switch(Read-Host "Режим") {
        "0" {$s.GameFilter="off"}
        "1" {$s.GameFilter="all"}
        "2" {$s.GameFilter="tcp"}
        "3" {$s.GameFilter="udp"}
        default {return}
    }
    Save-V2Settings $s
}

function Configure-V2IPSet {
    $s=Get-V2Settings
    Write-Host "1 loaded | 2 none | 3 any"
    switch(Read-Host "Режим") {
        "1" {$s.IPSetMode="loaded"}
        "2" {$s.IPSetMode="none"}
        "3" {$s.IPSetMode="any"}
        default {return}
    }
    Save-V2Settings $s
}

function Configure-V2Fake([string]$Kind) {
    $s=Get-V2Settings
    $files=@(Get-ChildItem -LiteralPath $Bin -File -Filter "*.bin" | Where-Object {$_.Name -notlike "ACTIVE_*"} | Sort-Object Name)
    for($i=0;$i -lt $files.Count;$i++) {
        $hash=(Get-FileHash -LiteralPath $files[$i].FullName -Algorithm SHA256).Hash.Substring(0,12)
        Write-Host ("  {0,2}. {1} [{2}]" -f ($i+1),$files[$i].Name,$hash)
    }
    $value=Read-Host "$Kind fake"
    $number=0
    if(-not[int]::TryParse($value,[ref]$number)) {
        return
    }
    if($number -lt 1 -or $number -gt $files.Count) {
        return
    }
    if($Kind -eq "Discord") {
        $s.DiscordFake=$files[$number-1].Name
    } else {
        $s.GameFake=$files[$number-1].Name
    }
    Save-V2Settings $s
}

function Remove-V2Service {
    foreach($name in @($ServiceName,$PreviousServiceName,$LegacyServiceName)) {
        $svc=Get-Service -Name $name -ErrorAction SilentlyContinue
        if($null -ne $svc) {
            Stop-Service -Name $name -Force -ErrorAction SilentlyContinue
            & sc.exe delete $name | Out-Null
            Start-Sleep -Seconds 1
        }
    }
    Stop-Winws
}

function Install-V2Service([string]$Name) {
    Assert-Runtime
    Remove-V2Service
    $argLine=Get-ProfileArguments $Name
    $binaryPath='"'+$Winws+'" '+$argLine
    New-Service -Name $ServiceName -BinaryPathName $binaryPath -DisplayName "NetHawk" -StartupType Automatic | Out-Null
    New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$ServiceName" -Name "NetHawkProfile" -Value $Name -PropertyType String -Force | Out-Null
    Start-Service -Name $ServiceName
}

function Update-V2IPSet {
    Ensure-V2Directories
    $url="https://raw.githubusercontent.com/$FlowsealRepo/main/.service/ipset-service.txt"
    $dest=Join-Path $Lists "ipset-all.txt"
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $dest -TimeoutSec 30
    Copy-Item $dest (Join-Path $Lists "ipset-all.txt.backup") -Force
    Write-Host "[OK] IPSet обновлён."
}

function Action-Status {
    Show-Header
    $s=Get-V2Settings
    if(Get-Process -Name "winws" -ErrorAction SilentlyContinue) {
        Write-Host "winws.exe: RUNNING"
    } else {
        Write-Host "winws.exe: STOPPED"
    }
    $svc=Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if($null -eq $svc) {
        Write-Host "Служба NetHawk: НЕ УСТАНОВЛЕНА"
    } else {
        Write-Host ("Служба NetHawk: {0}" -f $svc.Status)
    }
    $legacy=Get-Service -Name $LegacyServiceName -ErrorAction SilentlyContinue
    if($null -ne $legacy) {
        Write-Host ("[!] Найдена старая служба DPIBypass: {0}" -f $legacy.Status)
    }
    Write-Host ("Game Filter: {0}" -f $s.GameFilter)
    Write-Host ("IPSet: {0}" -f $s.IPSetMode)
    Write-Host ("Discord fake: {0}" -f $s.DiscordFake)
    Write-Host ("Game fake: {0}" -f $s.GameFake)
}

function Action-Service {
    Require-Administrator
    while($true) {
        Clear-Host
        Show-Header
        $s=Get-V2Settings
        Write-Host "1. Установить профиль как службу"
        Write-Host "2. Удалить службу"
        Write-Host "3. Статус"
        Write-Host ("4. Game Filter [{0}]" -f $s.GameFilter)
        Write-Host ("5. IPSet Filter [{0}]" -f $s.IPSetMode)
        Write-Host ("6. Discord fake [{0}]" -f $s.DiscordFake)
        Write-Host ("7. Game fake [{0}]" -f $s.GameFake)
        Write-Host "8. Синхронизировать ресурсы"
        Write-Host "9. Обновить IPSet"
        Write-Host "10. Диагностика"
        Write-Host "11. Тестер профилей"
        Write-Host "0. Выход"
        switch(Read-Host "Выбери") {
            "1" {$p=Select-V2Profile;if($p){Install-V2Service $p};Read-Host "Enter" | Out-Null}
            "2" {Remove-V2Service;Read-Host "Enter" | Out-Null}
            "3" {Action-Status;Read-Host "Enter" | Out-Null}
            "4" {Configure-V2GameFilter;Read-Host "Enter" | Out-Null}
            "5" {Configure-V2IPSet;Read-Host "Enter" | Out-Null}
            "6" {Configure-V2Fake "Discord";Read-Host "Enter" | Out-Null}
            "7" {Configure-V2Fake "Game";Read-Host "Enter" | Out-Null}
            "8" {Sync-V2Resources;Read-Host "Enter" | Out-Null}
            "9" {Update-V2IPSet;Read-Host "Enter" | Out-Null}
            "10" {Action-Diagnostics;Read-Host "Enter" | Out-Null}
            "11" {Action-Test;Read-Host "Enter" | Out-Null}
            "0" {return}
        }
    }
}

function Action-Test {
    Require-Administrator
    Assert-Runtime

    $tester = Join-Path $Root "utils\NetHawkTester.ps1"
    if (-not (Test-Path -LiteralPath $tester)) {
        throw "Не найден расширенный тестер: $tester"
    }

    $servicesToRestore = @()
    foreach ($name in @($ServiceName,$PreviousServiceName,$LegacyServiceName)) {
        $service = Get-Service -Name $name -ErrorAction SilentlyContinue
        if ($null -ne $service -and $service.Status -eq "Running") {
            Write-Host ("[INFO] Временно останавливаю службу {0}..." -f $name) -ForegroundColor DarkGray
            Stop-Service -Name $name -Force -ErrorAction Stop
            $servicesToRestore += $name
        }
    }

    if ($servicesToRestore.Count -gt 0) {
        Start-Sleep -Seconds 1
    }

    try {
        & $tester
    } finally {
        Stop-Winws
        foreach ($name in $servicesToRestore) {
            Write-Host ("[INFO] Восстанавливаю службу {0}..." -f $name) -ForegroundColor DarkGray
            Start-Service -Name $name -ErrorAction SilentlyContinue
        }
    }
}

function Action-Diagnostics {
    Show-Header
    try {
        Assert-Runtime
        Write-Host "[OK] Ресурсы комплектны."
    } catch {
        Write-Host ("[X] {0}" -f $_.Exception.Message)
    }
    $bfe=Get-Service -Name "BFE" -ErrorAction SilentlyContinue
    if($null -ne $bfe -and $bfe.Status -eq "Running") {
        Write-Host "[OK] BFE"
    } else {
        Write-Host "[X] BFE"
    }
    foreach($n in @("GoodbyeDPI","zapret","discordfix_zapret","winws1","winws2")) {
        if(Get-Service -Name $n -ErrorAction SilentlyContinue) {
            Write-Host ("[!] Возможный конфликт: {0}" -f $n)
        }
    }
    foreach($d in @("youtube.com","discord.com")) {
        try {
            Resolve-DnsName $d -ErrorAction Stop | Out-Null
            Write-Host ("[OK] DNS {0}" -f $d)
        } catch {
            Write-Host ("[X] DNS {0}" -f $d)
        }
    }
    Action-Status
}

function Action-SelfTest {
    Show-Header
    Assert-Runtime
    $count=0
    foreach($item in Get-ProfileCatalogV2) {
        $a=[string](Get-ProfileArguments $item.Key)
        if($a -notmatch "--wf-tcp=" -or $a -notmatch "--wf-udp=") {
            throw "$($item.Key): wf filters missing"
        }
        if($a -match "%(BIN|LISTS|GameFilter)") {
            throw "$($item.Key): unresolved variable"
        }
        foreach($m in [regex]::Matches($a,'"([^"]+\.(?:bin|txt))"')) {
            if(-not(Test-Path -LiteralPath $m.Groups[1].Value)) {
                throw "$($item.Key): missing $($m.Groups[1].Value)"
            }
        }
        $count++
        Write-Host ("[OK] {0}: {1} chars" -f $item.Key,$a.Length)
    }
    Write-Host ("[OK] SelfTest profiles={0}" -f $count)
}

function Action-Bootstrap {
    Sync-V2Resources
}

function Action-V2Menu {
    Clear-Host
    Show-Header
    $p=Select-V2Profile
    if($p) {
        if(-not (Test-Administrator)) {
            $argLine='-NoLogo -NoProfile -ExecutionPolicy Bypass -File "{0}" -Action "Run" -Profile "{1}"' -f $PSCommandPath,$p
            Start-Process -FilePath "powershell.exe" -Verb RunAs -ArgumentList $argLine | Out-Null
            return
        }
        Start-Profile $p
        Write-Host ("[OK] Started: {0}" -f $p)
    }
}

$CustomLayer = Join-Path $PSScriptRoot "NetHawk.Custom.ps1"
if (Test-Path -LiteralPath $CustomLayer) {
    . $CustomLayer
}

try {
    switch ($Action) {
        "Menu"        { Action-V2Menu }
        "Run"         { Action-Run }
        "Test"        { Action-Test }
        "Service"     { Action-Service }
        "Diagnostics" { Action-Diagnostics }
        "Status"      { Action-Status }
        "Stop"        { Action-Stop }
        "Bootstrap"   { Action-Bootstrap }
        "Sync"        { Sync-V2Resources }
        "UpdateIPSet" { Update-V2IPSet }
        "SelfTest"    { Action-SelfTest }
        "Ports"       { Action-Ports }
        "Profiles"    { Action-Profiles }
        "PortScout"   { Action-PortScout }
    }
    if ($KeepOpen) {
        Write-Host ""
        Read-Host "Тест завершён. Нажмите Enter, чтобы закрыть окно" | Out-Null
    }
    exit 0
} catch {
    Write-Host ""
    Write-Host ("[ОШИБКА] {0}" -f $_.Exception.Message) -ForegroundColor Red
    if ($KeepOpen) {
        Write-Host ""
        Read-Host "Нажмите Enter, чтобы закрыть окно" | Out-Null
    }
    exit 1
}
