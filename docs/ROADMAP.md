# Roadmap NetHawk

## Adaptive Tester

Baseline без winws → тест профилей → сравнение улучшений/регрессий → рекомендации → создание user profile.

Отдельно различать DNS, TCP connect, TLS, HTTP, QUIC, UDP и STUN/Discord Voice там, где это технически возможно. Показывать не только абсолютный результат, а что стратегия исправила относительно baseline.

## Composite Profile Builder

Собирать один пользовательский профиль из разных strategy blocks для разных классов трафика.

## Network Fingerprints

Запоминать рабочий profile/config для разных сетей и предлагать его при смене сети.

## Strategy Diff

При смене Flowseal pin показывать понятный diff параметров: repeats, split-pos, fake, filters.

## Explain My Strategy

Разбирать effective `winws` command: какой block за что отвечает, какие ports/lists/IPSet используются и откуда пришёл параметр.

## Last Known Good

Хранить последний рабочий profile + pin + settings + ports + overrides + hashes и давать быстрый rollback.

## Portable Profile Packs

Экспорт/импорт Base + Overrides + Custom ports + Raw args + expected upstream pin без упаковки чужого runtime.

## Port Scout 2

- фильтрация noisy/ephemeral ports;
- confidence/frequency;
- before/after capture;
- startup traffic vs action traffic;
- remote UDP correlation через ETW/WinDivert, если получится надёжно;
- сравнение с effective strategy coverage.

## Configuration migration

Версионированная schema для settings/ports/profile overrides с backup и безопасной миграцией.

## Branding / desktop integration

- production ICO 16/24/32/48/64/128/256;
- чёрная/белая версии;
- transparent PNG;
- micro-mark для 16×16.
