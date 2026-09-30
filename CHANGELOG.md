# История изменений

## 0.3.0-dev1

- Проект переименован из **NetLayer** в **NetHawk**.
- Launcher: `NetHawk.bat`.
- Engine: `scripts/NetHawk.ps1`; custom layer: `scripts/NetHawk.Custom.ps1`; tester: `utils/NetHawkTester.ps1`.
- Windows service переименована в `NetHawk`; `NetLayer` и `DPIBypass` поддерживаются как legacy migration targets.
- Release workflow собирает `NetHawk-<version>.zip`.
- Добавлены roadmap, заметки по разработке и brand guide.

## 0.2.0-dev5

- Добавлены глобальные пользовательские TCP/UDP-порты без редактирования upstream BAT-файлов.
- Добавлены Profile Overrides: пользовательский профиль хранит Base + собственные TCP/UDP + Raw Extra Arguments.
- Пользовательские настройки вынесены в `config/ports-user.json` и `config/profiles-user/` и не затираются синхронизацией upstream.
- Пользовательские профили доступны для обычного запуска и установки как Windows-служба.
- Добавлен Port Scout: наблюдение за TCP/UDP endpoint'ами выбранного процесса и перенос найденных портов в NetHawk.
- Port Scout умеет добавлять порты глобально, создавать новый override или дополнять существующий.
- Добавлены логи Port Scout в `logs/port-scout/`.
- Главное меню и Service Manager дополнены новыми функциями.
- Self-test теперь проверяет custom TCP/UDP на всех 21 профилях и отдельный временный пользовательский override.
- Custom-layer вынесен в `scripts/NetHawk.Custom.ps1`.

## 0.2.0-dev4

- Тестер переработан на расширенную схему Flowseal с сохранением отдельной NetHawk-интеграции.
- Добавлен режим стандартных тестов: HTTP / TLS 1.2 / TLS 1.3 / Ping.
- Добавлены targets Discord, YouTube, Google, Cloudflare и публичных DNS.
- Добавлен DPI checker TCP 16–20 KB freeze по target suite проекта hyperion-cs/dpi-checkers.
- Можно тестировать все 21 профиля или выбранные номера/диапазоны.
- Консоль использует читаемую палитру: cyan/info, green/OK, yellow/warnings/UNSUP, red/FAIL/BLOCKED.
- Для DPI-теста IPSetMode временно переключается в any через settings.json и восстанавливается после завершения.
- Добавлен recovery backup для аварийно прерванного DPI-теста.
- Итог показывает рекомендуемые для дальнейшей проверки стратегии, а не одного искусственного победителя.
- Результаты сохраняются в logs/tester/latest.txt, latest.csv и runs/.
- Тестер временно останавливает NetHawk/legacy DPIBypass service и восстанавливает после теста.
- Добавлены attribution Flowseal tester и hyperion-cs/dpi-checkers.
- Windows CI теперь парсит и основной движок, и utils/NetHawkTester.ps1.

## 0.2.0-dev3

- Тестер теперь сохраняет результаты каждого прогона в \`logs/tester/\`.
- Добавлены \`latest.txt\`, \`latest.csv\` и отдельный подробный лог каждого запуска в \`logs/tester/runs/\`.
- После полного прогона выводится таблица всех профилей и список стратегий с максимальным результатом.
- Если ни один профиль не получил 3/3, тестер отдельно показывает лучший доступный результат.
- Рекомендации явно ограничены текущими HTTPS-проверками; Discord Voice, QUIC и игровой UDP не выдаются за подтверждённые.
- \`tester.bat\` больше не теряет окно после UAC-перезапуска: консоль остаётся открытой до нажатия Enter.
- README дополнен разделом о результатах и логах тестера.

## 0.2.0-dev2

- Project renamed from **DPIBypass** to **NetHawk**.
- Main launcher renamed to \`NetHawk.bat\`; PowerShell engine renamed to \`scripts/NetHawk.ps1\`.
- Windows service renamed to \`NetHawk\`; legacy \`DPIBypass\` service is detected/cleaned during migration.
- Program header now visibly credits Flowseal/zapret-discord-youtube and bol-van/zapret.
- README completely redesigned with an original NetHawk layout, prominent project lineage, upstream-vs-NetHawk responsibility table, architecture and roadmap.
- Third-party attribution and architecture docs updated.
- Release artifacts are now named \`NetHawk-<version>.zip\`.

## 0.2.0-dev1

- Добавлен полный профильный слой: General, ALT1–ALT12, EXP, FAKE TLS AUTO и SIMPLE FAKE варианты.
- Профили синхронизируются из закреплённого Flowseal commit и читаются как данные.
- Standalone и Windows-служба используют один генератор аргументов.
- Добавлены list-general/list-google/list-exclude и ipset-* режимы.
- Добавлены Game Filter: off / TCP+UDP / TCP / UDP.
- Добавлены IPSet modes: loaded / none / any.
- Добавлен выбор fake payload отдельно для Discord UDP и GameFilter UDP.
- В ресурсный набор входят QUIC/TLS/STUN payloads.
- Добавлен tools/sync-resources.bat.
- Добавлен DPIBypass.bat с выбором профиля.
- CI синхронизирует и валидирует полный набор перед релизом.

## 0.1.0-dev4

- Исправлен конфликт со встроенной PowerShell переменной Host.
- Добавлен self-test генератора профилей.

## 0.1.0-dev3

- Пользовательские BAT заменены на ASCII-only launchers.
- Основная логика перенесена в PowerShell.
- Добавлен Windows smoke-test.
