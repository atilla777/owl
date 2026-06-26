---
status: passed
summary: >-
  Версия Owl экспонирована через CLI (owl version, config get version алиас,
  owl-блок в config show); синхрон init/upgrade закрыт регресс-тестами. Полный
  rspec зелёный (2063 examples, 0 failures), rubocop чист по затронутым файлам,
  все smoke-команды проходят.
---

# Summary

Реализована экспозиция версии Owl через CLI согласно плану TASK-0046. Изменения
аддитивны (новая команда, read-алиас, расширение вывода `config show`), хранилищный
ключ остаётся `owl.version`. Версия гема повышена по minor (1.0.0 → 1.1.0) с записью
в `CHANGELOG.md`.

Сделано:

- `lib/owl/config/api.rb` — `READ_ALIASES = { 'version' => 'owl.version' }`;
  `read_key` резолвит алиас, но возвращает запрошенный `key`; `write_key`
  отклоняет запись в алиас ошибкой `config_key_aliased`.
- `lib/owl/config/backends/filesystem.rb#snapshot` — добавлен `owl:`-блок
  (`document.owl_section`), теперь виден в `config show`.
- `lib/owl/version/api.rb` (новый публичный модуль) — `Owl::Version::Api.info(root:)`
  → `{ gem:, project:, up_to_date: }`; legacy без штампа → `project: nil`,
  `up_to_date: false`.
- `lib/owl/cli/internal/commands/version.rb` (новая тонкая команда) +
  регистрация `'version'` в `SIMPLE_COMMANDS` (`lib/owl/cli/api.rb`); флаг
  `owl --version` не тронут и сосуществует с подкомандой.
- `lib/owl/version.rb` — bump 1.0.0 → 1.1.0; запись в `CHANGELOG.md`.
- Тесты: `spec/owl/version/api_spec.rb` (drift/match/legacy), расширения в
  `spec/owl/config/api_spec.rb` (read-алиас, write-отказ, owl-блок snapshot),
  `spec/owl/cli/api_spec.rb` (owl version, config get/set version, owl-блок в
  show, флаг --version), регресс-тесты синхрона в `spec/owl/init/api_spec.rb` и
  `spec/owl/upgrade/refresh_spec.rb`. Файл `version.rb` добавлен в FS-allowlist
  конституционного теста (тот же паттерн `Pathname.new(...).expand_path`, что и
  config_get/show).

# Commands

```
bundle exec rspec spec/owl/config spec/owl/cli spec/owl/version spec/owl/init spec/owl/upgrade/refresh_spec.rb
bundle exec rspec
bundle exec rubocop lib/owl/config/api.rb lib/owl/config/backends/filesystem.rb lib/owl/version/api.rb lib/owl/cli/internal/commands/version.rb lib/owl/cli/api.rb lib/owl/version.rb
bin/owl config get version --json
bin/owl config show --json
bin/owl version --json
bin/owl config set version 9.9.9 --json
bin/owl --version
```

# Outcomes

- **Полный rspec:** `2063 examples, 0 failures, 1 pending` (pending —
  pre-existing concurrent-write contract заглушка, не относится к задаче).
- **Coverage:** line 97.12% общий; SimpleCov-гейт 100% для `lib/owl/**/api.rb`
  пройден (включая новый `lib/owl/version/api.rb`) — список «below 100%» в полном
  прогоне пуст.
- **RuboCop по затронутым файлам:** `6 files inspected, no offenses detected`.
- **Smoke:**
  - `config get version` → `{"ok":true,"key":"version","value":"0.21.0"}` (не null).
  - `config show` → `owl` блок содержит `version: "0.21.0"`.
  - `owl version` → `{"gem":"1.1.0","project":"0.21.0","up_to_date":false}` —
    канонический self-hosted drift отображён корректно.
  - `config set version 9.9.9` → отказ `config_key_aliased`.
  - `owl --version` → `owl 1.1.0` (флаг гема не сломан).

# Not run

Не запускалось ничего сверх плана. Сборка/установка гема и `owl upgrade` в
консьюмерах — вне охвата шага implement (propagation выполняется отдельно после
commit_push).

# Failures or blockers

Нет. Один pre-existing pending в `spec/owl/storage/backends/shared/backend_contract.rb`
(concurrent-write semantics) не связан с задачей.

# Residual risks

- Read-алиас `version` затрагивает всех потребителей `read_key`; риск низкий —
  карта добавляет резолв ранее-отсутствовавшего ключа, существующие ключи не
  меняются (покрыто тестами на `owl.version` и прочие пути).
- `config show` теперь отдаёт дополнительный `owl`-блок; аддитивно, существующие
  потребители читают по своим ключам и не падают.
- `owl.version` в этом репозитории намеренно отстаёт от гема (0.21.0 vs 1.1.0) —
  это ожидаемый self-hosted drift, который `owl version` и призван показывать.
