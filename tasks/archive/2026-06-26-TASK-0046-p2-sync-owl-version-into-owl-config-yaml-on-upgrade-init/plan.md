---
status: approved
summary: >-
  Алиас version→owl.version в Config::Api (read резолвит, write отклоняет);
  snapshot отдаёт owl-блок (одна строка, owl_section уже парсится); новый
  Owl::Version::Api.info + команда owl version; регресс-тест синхрона init/upgrade;
  minor bump + changelog.
---

# Goal

Экспонировать версию Owl через CLI: `config get version` (алиас на
`owl.version`), `config show` (owl-блок), новая команда `owl version`
(gem vs project-stamped, с `up_to_date`). Синхрон init/upgrade сохранить и
закрыть регресс-тестом. Аддитивно → minor bump.

# Checklist

1. **`lib/owl/config/api.rb` — read-алиас.** Добавить
   `READ_ALIASES = { 'version' => 'owl.version' }.freeze`. В `read_key`
   резолвить ключ перед делегацией: `actual = READ_ALIASES.fetch(key, key)`,
   `read_key(key: actual)`, но в ответе вернуть **запрошенный** `key`
   (чтобы `config get version` отдавал `key: "version"`). Проверить, что
   `ConfigGet`-команда печатает запрошенный ключ.
2. **`lib/owl/config/api.rb` — write-guard.** В `write_key`: если
   `READ_ALIASES.key?(key)` → `Result.err(:config_key_aliased, message:
   "'version' is a read-only alias of 'owl.version'; set 'owl.version'
   instead.")`. Не писать алиас-ключ.
3. **`lib/owl/config/backends/filesystem.rb#snapshot` (стр. 103-117).**
   Добавить в возвращаемый хэш `owl: document.owl_section` (поле
   `owl_section` уже парсится, стр. 161). Так `config show` покажет
   `owl: { version: ... }`.
4. **Новый `lib/owl/version/api.rb` — `Owl::Version::Api.info(root:)`.**
   Возвращает `Result.ok(gem: Owl::VERSION, project: <owl.version|nil>,
   up_to_date: gem == project)`. `project` читать через
   `Owl::Config::Api.read_key(root:, key: 'owl.version')` (или `version`
   через алиас) → `nil`, если ключа нет (legacy). `up_to_date: false` при
   `project.nil?`. Публичный API → 100% coverage.
5. **Новый `lib/owl/cli/internal/commands/version.rb`.** Тонкая команда:
   резолвит root, зовёт `Owl::Version::Api.info`, печатает
   `{ ok: true, gem:, project:, up_to_date: }`. Поддержать `--root`,
   `--json`.
6. **`lib/owl/cli/api.rb` — регистрация.** `require_relative
   'internal/commands/version'`; добавить top-level команду `'version'` в
   COMMANDS-карту (стр. ~130) → новый dispatch. НЕ трогать обработку флага
   `--version`/`-V` (стр. 116) — это отдельный путь (gem), он остаётся.
   Убедиться, что `owl version` (subcommand) и `owl --version` (flag)
   сосуществуют.
7. **Регресс-тест синхрона.** Покрыть, что `owl init` пишет `owl.version =
   Owl::VERSION` и `owl upgrade` (refresh `stamp_version`) пере-штампует
   его. Не новый код — защита от регрессии.
8. **`lib/owl/version.rb` — minor bump** (1.0.0 → 1.1.0); запись в
   `CHANGELOG.md` (новая команда `owl version`, алиас `config get version`,
   owl-блок в `config show`). Один коммит.
9. **Specs** (см. ниже).

# Smoke test

```
bin/owl config get version --json    | python3 -c "import sys,json; d=json.load(sys.stdin); assert d['value'] is not None, d; print('get version OK', d['value'])"
bin/owl config show --json           | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'owl' in d and 'version' in d['owl'], d; print('show owl OK', d['owl'])"
bin/owl version --json               | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'gem' in d and 'project' in d and 'up_to_date' in d, d; print('owl version OK', d)"
bin/owl config set version 9.9.9 --json 2>&1 | python3 -c "import sys,json; d=json.load(sys.stdin); assert d['ok'] is False, d; print('set version rejected OK')"
bin/owl --version
bundle exec rspec spec/owl/config spec/owl/cli 2>&1 | tail -5
```

# Scope

- `lib/owl/config/api.rb` (read-алиас + write-guard).
- `lib/owl/config/backends/filesystem.rb` (#snapshot → owl-блок).
- `lib/owl/version/api.rb` (новый), `lib/owl/cli/internal/commands/version.rb`
  (новый), `lib/owl/cli/api.rb` (require + регистрация команды).
- `lib/owl/version.rb` + `CHANGELOG.md`.
- Specs под `spec/owl/config`, `spec/owl/cli`, `spec/owl/version`,
  регресс init/upgrade.

# Constraints

- Хранилищный ключ остаётся `owl.version`; `version` — read-only алиас.
- Синхрон init/upgrade НЕ меняем (только закрываем тестом).
- FS-доступ только через `Owl::Config::Api`/`Storage::Api` (layering).
- Флаг `owl --version` (gem) не ломать.
- 100% line coverage `lib/owl/**/api.rb` (вкл. новый `version/api.rb`).
- RuboCop чистый по затронутым файлам.

# Files to inspect

- `lib/owl/config/api.rb` (`read_key` стр. 35, `write_key` стр. 39).
- `lib/owl/config/backends/filesystem.rb` (`snapshot` стр. 103-117,
  `owl_section` стр. 161).
- `lib/owl/cli/internal/commands/config_get.rb` (печать `key`/`value`,
  `--strict`/null).
- `lib/owl/cli/internal/commands/config_show.rb` (зовёт `snapshot`).
- `lib/owl/cli/api.rb` (COMMANDS-карта стр. 130, `--version` стр. 116).
- `lib/owl/init/api.rb:33` (штамп), `lib/owl/upgrade/internal/refresh.rb`
  (`current_version`/`stamp_version` стр. 150-157).
- `lib/owl/version.rb`.

# Tests and verification

- `spec/owl/version/api_spec.rb` (новый): `info` — drift (gem≠project),
  match (gem==project), legacy (`project: nil`, `up_to_date: false`).
- `spec/owl/config/...`: `read_key('version')` резолвит `owl.version`;
  ответ несёт запрошенный `key: 'version'`; `write_key('version', …)`
  отклоняется `config_key_aliased`; `snapshot` содержит `owl`-блок.
- `spec/owl/cli/...`: `owl version --json` шейп; `config get version`
  не-null; `config show` owl-блок; `config set version` отказ; `owl
  --version` (gem) не сломан.
- Регресс: `owl init`/`owl upgrade` штампуют `owl.version = Owl::VERSION`.
- `bundle exec rspec` зелёный; SimpleCov 100% для api.rb; RuboCop чистый.
- Smoke-команды выше проходят.

# Out of scope

- TASK-0041: из неё исключается пункт «sync config version» (владелец —
  TASK-0046); ready/available overlap + clear-current-on-delete остаются
  за TASK-0041. Зафиксировать при работе над ней (здесь код не трогаем).
- Миграция on-disk ключа `owl.version` → top-level `version`.
- Изменение поведения флага `owl --version`.
- Автосамолечение штампа на произвольных командах (только init/upgrade).
