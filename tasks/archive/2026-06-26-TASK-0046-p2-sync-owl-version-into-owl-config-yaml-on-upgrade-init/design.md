---
status: shipped
summary: >-
  Алиас version→owl.version на чтение в Config::Api.read_key; config set version
  отклоняется (канон пишется в owl.version); config show отдаёт owl-блок; новая
  команда owl version через тонкий Owl::Version::Api.info → {gem, project,
  up_to_date}. Синхрон init/upgrade не трогаем, закрываем регресс-тестом.
---

# Context

Версия штампуется в `.owl/config.yaml` под `owl.version`
(`init/api.rb:33`, `upgrade/.../refresh.rb#stamp_version`). Пробелы — только
в экспозиции (бриф):

- `ConfigGet` (`cli/internal/commands/config_get.rb`) зовёт
  `Config::Api.read_key(key:)` и при `config_key_missing` без `--strict`
  отдаёт `value: nil`. Ключа `version` нет → `null`.
- `config show` строит курируемый вид (`project`/`settings`/`storage`) без
  `owl`-блока.
- Команды `version` нет; есть только флаг `owl --version` (gem).

Брифом оставлены на design: (1) поведение `config set version`,
(2) JSON-форма `owl version`, (3) где живёт алиас.

# Decision

1. **Алиас `version` → `owl.version` на чтение — в `Config::Api.read_key`.**
   Единая точка: и `config get version`, и любой внутренний reader получают
   значение. Реализация: маленькая константа-карта
   `READ_ALIASES = { 'version' => 'owl.version' }`; перед резолвом ключа
   `key = READ_ALIASES.fetch(key, key)`. `config get` менять не нужно
   (поведение `--strict`/null сохраняется поверх алиаса).
2. **`config set version` отклоняется** структурированной ошибкой
   (`config_key_aliased` или эквивалент) с подсказкой писать в `owl.version`.
   Запись каноном — только `owl.version`; молчаливый прокси записи не
   делаем (два write-пути → дрейф ожиданий). Алиас строго read-only.
3. **`config show` отдаёт `owl`-блок.** Добавить персистентный `owl` блок
   (включая `version`) в курируемый вывод `config show` — читать его из
   конфигурации тем же путём, что и остальные секции.
4. **Новая команда `owl version`** поверх тонкого API
   `Owl::Version::Api.info(root:)` → `{ gem:, project:, up_to_date: }`:
   - `gem` = `Owl::VERSION` (константа гема);
   - `project` = `Config::Api.read_key('owl.version')` (или `nil` для
     legacy без штампа);
   - `up_to_date` = `gem == project` (при `project == nil` → `false`).
   CLI-команда `cli/internal/commands/version.rb` тонкая: зовёт API,
   печатает JSON. Флаг `owl --version` (gem) не трогаем.

Слой: логика в `lib/owl/version/api.rb` (новый публичный модуль, 100%
coverage) + алиас в `config/api.rb`; CLI-команды тонкие делегаты.
Аддитивно (новый ключ-алиас, новая команда, расширение show) → **minor
bump** + `CHANGELOG.md`. Хранилищный ключ остаётся `owl.version`.

# Alternatives

1. **Алиас только в `config_get`-команде.** Отклонено: знание об алиасе
   утекает в CLI-слой, остальные readers `version` по-прежнему дают `null`;
   единая точка в `read_key` чище.
2. **`config set version` проксирует в `owl.version`.** Отклонено: два
   write-пути к одному значению, риск рассинхрона ожиданий; явный отказ
   честнее (read-only алиас).
3. **Top-level ключ `version` вместо `owl.version` (миграция).** Отклонено:
   ломает существующий синхрон init/upgrade и требует миграции
   `config.yaml`; алиас на чтение решает задачу без миграции.
4. **`owl version` читает FS/`config.yaml` напрямую.** Отклонено: нарушает
   layering (FS-доступ только через Api); идём через `Config::Api.read_key`.
5. **Без отдельного `Owl::Version::Api`, логика в команде.** Отклонено:
   правило 100% coverage для публичного API + тестируемость → тонкий API.

# Risks

- **Алиас в `read_key` затрагивает всех потребителей.** Низкий риск: карта
  добавляет резолв ранее-отсутствовавшего ключа `version`; существующие
  ключи не меняются. Покрыть тестом, что `owl.version` и прочие ключи
  читаются как прежде.
- **`config set version` теперь ошибка.** Поведенческое изменение, но ключа
  раньше и не было (set version писал бы новый бесполезный ключ). Покрыть
  тестом на отказ с понятным сообщением.
- **`config show` форма меняется** (добавляется `owl`-блок) — аддитивно;
  убедиться, что потребители show не падают на новом ключе.
- **Legacy без `owl.version`.** `info` и `config get version` обязаны
  возвращать `nil` без падения; `up_to_date: false`.
- **Coverage/RuboCop** по новым `version/api.rb` и командам.

# API

`owl config get version --json` (алиас на `owl.version`):

```json
{ "ok": true, "key": "version", "value": "1.0.0" }
```

`owl config set version X` — отклонение:

```json
{ "ok": false, "error": { "code": "config_key_aliased",
  "message": "'version' is a read-only alias of 'owl.version'; set 'owl.version' instead." } }
```

`owl config show --json` — добавляется `owl`-блок:

```json
{ "ok": true, "project": { … }, "settings": { … }, "storage": { … },
  "owl": { "version": "1.0.0" } }
```

`owl version --json`:

```json
{ "ok": true, "gem": "1.0.0", "project": "0.21.0", "up_to_date": false }
```

`Owl::Version::Api.info(root:)` → `Result.ok(gem:, project:, up_to_date:)`.

Вне охвата: флаг `owl --version` (gem, без изменений); on-disk ключ
хранения `owl.version`; синхрон init/upgrade (сохраняется, закрывается
регресс-тестом).
