---
status: resolved
summary: "Версия Owl теперь доступна через CLI (owl version, config get/show); реализация корректна, тесты и rubocop зелёные, замечаний-блокеров нет"
verdict: accepted
ready: true
---

# Code review

## Summary

Задача TASK-0046 — сделать застампованную версию Owl (`owl.version` в
`.owl/config.yaml`) видимой через CLI. Реализованы три аддитивных канала:

- `owl version` — новая команда, печатает версию гема (`Owl::VERSION`),
  версию проекта (`owl.version`) и флаг `up_to_date` (дрейф).
- `owl config get version` — `version` теперь read-only алиас на
  `owl.version`; `owl config set version` отклоняется кодом
  `config_key_aliased`.
- `owl config show` — снапшот теперь содержит блок `owl` (с `version`).

Плюс новый модуль `Owl::Version::Api.info(root:)`, регистрация команды в
`SIMPLE_COMMANDS`, бамп версии 1.0.0 → 1.1.0 и запись в CHANGELOG.

Диф полностью соответствует brief/design/plan: фокус строго аддитивный,
без миграций on-disk формата, флаг `owl --version` (только гем) не тронут
и сосуществует с подкомандой.

## Findings

Проверены все пункты review-focus; функциональные дефекты не обнаружены.

1. **`config get version` → ключ `version`, значение из `owl.version`** —
   OK. `read_key` резолвит алиас в `actual = 'owl.version'`, но при успехе
   возвращает `Result.ok(key: 'version', value: ...)` — запрошенный ключ не
   переписывается молча. Ручная проверка: `{"ok":true,"key":"version","value":"0.21.0"}`.
   `config get owl.version` по-прежнему работает.

2. **`config set version` отклоняется** — OK. Структурированная ошибка
   `config_key_aliased` с `details: {key, canonical}` и понятным сообщением
   (`'version' is a read-only alias of 'owl.version'; set 'owl.version' instead.`).
   Канонический путь записи (`owl.version`) остаётся единственным.

3. **`config show` содержит блок `owl`** — OK. `snapshot` отдаёт
   `owl: document.owl_section`. Потребителей снапшота новый ключ не ломает
   (полный прогон `spec/owl/config`, `spec/owl/cli` зелёный).

4. **`owl version` + legacy** — OK. `Owl::Version::Api.info` отдаёт
   `project: nil`, `up_to_date: false` для проектов без стампа (без краха),
   покрыто отдельным тестом. Реальный прогон: gem 1.1.0 / project 0.21.0 /
   up_to_date false (корректное обнаружение дрейфа).

5. **`owl --version` (флаг гема)** — OK. По-прежнему печатает `owl 1.1.0`,
   сосуществует с подкомандой (отдельный тест на совместимость).

6. **Sync на init/upgrade** — OK. Стампинг не менялся, добавлены
   регрессионные тесты в `spec/owl/init/api_spec.rb` (init стампит
   `Owl::VERSION`) и `spec/owl/upgrade/refresh_spec.rb` (upgrade
   ре-стампит `from→to`).

7. **MINOR-бамп 1.1.0** — корректен: изменения чисто аддитивные, без
   слома on-disk формата / CLI-контракта / `required_sections`. CHANGELOG
   точно описывает все три канала и новый модуль.

8. **Слоистость / отсутствие прямого FS** — OK. `version.rb` (CLI) и
   `version/api.rb` не читают FS напрямую: идут через
   `Owl::Storage::Api.detect_root` и `Owl::Config::Api`. Добавление
   `cli/internal/commands/version.rb` в allowlist `no_direct_fs_spec`
   оправдано тем же паттерном, что у прочих `config_*`-команд (использование
   `Pathname` для резолва root), а не реальным доступом к ФС.

9. **Алиас не ломает других потребителей `read_key`** — OK. Все вызовы
   (`init`/`upgrade` чтение `settings.agent_targets` и `owl.version`,
   `claim_service` TTL, `verification/engine`, `config_get`) используют
   конкретные канонические ключи; никто не запрашивает буквально `version`,
   так что `READ_ALIASES` срабатывает только для нового пути.

10. **Покрытие** — `lib/owl/version/api.rb` и `lib/owl/config/api.rb` НЕ
    попали в список «ниже 100%», т.е. покрыты на 100%. Остальные api.rb в
    списке — известный артефакт частичного прогона SimpleCov (полный набор
    спеков не запускался), а не регрессия данной задачи.

## Resolution

Все находки — информационные/подтверждающие; блокеров нет. Каждый пункт
review-focus подтверждён кодом, тестом или ручным прогоном CLI.

Проверки:
- `bundle exec rspec spec/owl/config spec/owl/cli spec/owl/version spec/owl/init spec/owl/upgrade` → **592 examples, 0 failures**.
- `bundle exec rubocop` по затронутым файлам → **5 files, no offenses**.
- Ручной прогон `bin/owl version`, `--version`, `config get/set version`,
  `config get owl.version` → поведение соответствует спецификации.

## Remediation

Не требуется — verdict `accepted`, blocking-дефектов нет.

## Residual risks

- **Низкий: `config show` отдаёт весь блок `owl`, а не только `version`.**
  В реальном конфиге `owl` содержит ещё `control_root` (путь), который
  теперь виден в `config show`. Не секрет и не дефект, но шире, чем «owl
  block (with version)» из CHANGELOG. При желании можно сузить до
  whitelisted-полей в будущем.
- **Низкий: разная отчётность ключа в alias-пути.** При успехе
  `config get version` возвращает запрошенный ключ (`version`), а при
  ошибке (legacy без стампа) — `config_key_missing`, ссылающийся на
  канонический `owl.version`. Косметическая несогласованность, на контракт
  и тесты не влияет.
