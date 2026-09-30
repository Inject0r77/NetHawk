# Разработка NetHawk

## Текущее состояние

NetHawk — Windows network strategy/orchestration layer поверх Flowseal/zapret-discord-youtube, bol-van/zapret и WinDivert.

Репозиторий: `Inject0r77/NetHawk`  
Ветка разработки: `main`  
Текущая dev-линия: `0.3.0-dev1`

История названий: `DPIBypass → NetLayer → NetHawk`.

## Уже реализовано

- 21 upstream-профиль;
- единый parser/effective-arguments path для run/service/tester/self-test;
- Windows Service Manager;
- Game Filter / IPSet modes / fake payload selection;
- HTTP / TLS / Ping tester;
- TCP 16–20 KB DPI checker;
- логи и итоговые рекомендации тестера;
- global custom TCP/UDP;
- Profile Overrides;
- Raw Extra Arguments;
- Port Scout;
- pinned upstream synchronization;
- Windows CI/self-test.

## Важные детали

1. Кириллические `.ps1` хранить в UTF-8 с BOM для Windows PowerShell 5.1.
2. BAT launchers должны оставаться ASCII + CRLF.
3. Release ZIP содержит одну верхнюю папку `NetHawk-<version>/`.
4. После изменения ports/override у уже установленной службы профиль нужно установить как службу заново.
5. Tester не должен оставлять IPSet или службу в изменённом состоянии.
6. Sync не должен перетирать пользовательские файлы.
7. HTTPS test не считается подтверждением Discord Voice, QUIC или игрового UDP.

## Пользовательские данные

Не перезаписывать при Sync:

- `config/settings.json`;
- `config/ports-user.json`;
- `config/profiles-user/`;
- user list/IPSet overrides.

## Технический долг

- постепенно очистить старые/новые повторные определения функций в engine без изменения поведения;
- усилить проверку HTTP blockpages и redirects;
- улучшить UDP correlation в Port Scout;
- добавить versioned config migration;
- подготовить production ICO и micro-mark для 16×16/32×32.

## Следующий крупный блок

- Adaptive Tester;
- Composite Profile Builder.
