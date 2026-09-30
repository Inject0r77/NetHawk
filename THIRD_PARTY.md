# Third-party components and project lineage

NetHawk is an independent derivative project. It is not an official build of Flowseal or bol-van.

## Lineage

\`\`\`text
NetHawk
└── adapted from Flowseal/zapret-discord-youtube
    └── built on bol-van/zapret + zapret-win-bundle
        └── Windows packet filtering via WinDivert
\`\`\`

## Flowseal/zapret-discord-youtube

Repository: https://github.com/Flowseal/zapret-discord-youtube

NetHawk adapts and/or synchronizes upstream strategy profiles, host/IP lists, fake payload resources, and several Windows workflow concepts from Flowseal's project.

The currently pinned profile/resource baseline is:

\`\`\`text
commit 249a70424aae2676f99c5363e21073ed89873eda
\`\`\`

These files remain third-party material. NetHawk's own profile parser, orchestration, service integration, validation pipeline, and future override/adaptive layers are maintained separately.

Flowseal's repository carries the following MIT copyright notices:

Copyright (c) 2016-2026 bol-van  
Copyright (c) 2024-2026 Flowseal

See LICENSE-THIRD-PARTY.txt for the MIT license text shipped with this project.

## bol-van/zapret

Repository: https://github.com/bol-van/zapret

Used as the core DPI-desynchronization engine. NetHawk does not claim authorship of \`winws\`, zapret's desynchronization techniques, or its core runtime behavior.

## bol-van/zapret-win-bundle

Repository: https://github.com/bol-van/zapret-win-bundle

Used as an upstream source/reference for the Windows runtime packaging, including components such as:

- \`winws.exe\`
- \`WinDivert.dll\`
- \`WinDivert64.sys\`
- \`cygwin1.dll\`

## WinDivert

Repository: https://github.com/basil00/WinDivert

WinDivert provides Windows packet capture/filtering used by the runtime. WinDivert is distributed under its own licensing terms (LGPLv3 or GPLv2 options as documented by the upstream project).

## NetHawk-specific code

NetHawk-specific work includes the orchestration layer around upstream resources, including:

- profile-as-data parsing;
- one effective argument path for standalone and service modes;
- pinned upstream synchronization;
- minimal BAT launchers;
- Windows CI validation and release gating;
- NetHawk-specific configuration and service management;
- planned custom profile overrides and adaptive testing.

Third-party components retain their own copyright and license terms.


## Flowseal test framework

Расширенный тестер NetHawk (`utils/NetHawkTester.ps1`) адаптирует идеи и значительную часть тестовой механики из:

- https://github.com/Flowseal/zapret-discord-youtube
- исходный файл: `utils/test zapret.ps1`
- закреплённая ревизия: `249a70424aae2676f99c5363e21073ed89873eda`
- лицензия upstream: MIT.

Файл NetHawk существенно изменён: русифицирован интерфейс, изменён запуск профилей, работа с IPSet переведена на `config/settings.json`, добавлены собственные рекомендации, логи и интеграция со службой NetHawk.

## hyperion-cs/dpi-checkers

Репозиторий: https://github.com/hyperion-cs/dpi-checkers

DPI-режим тестера использует публичный TCP 16–20 KB target suite проекта `hyperion-cs/dpi-checkers`:

- https://hyperion-cs.github.io/dpi-checkers/ru/tcp-16-20/suite.v2.json
- лицензия проекта: Apache-2.0.

NetHawk не выдаёт DPI checker suite за собственную разработку.
