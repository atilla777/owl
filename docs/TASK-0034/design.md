---
status: shipped
summary: "Чисто CLI-слой: spec_apply.rb#emit добавляет unchanged в JSON; spec_merge.rb#json_payload выносит unchanged на верх; spec_merge.rb печатает unchanged-строку в summary (nil-safe). Движок merge/apply не трогаем."
---

# Context

Движок (TASK-0029) считает `unchanged: {added, modified, removed}` и возвращает
через `Specs::Api.apply` (поле `unchanged`) и `merge_task` (внутри `merge`
под-объекта). Пробел — в CLI-рендере:
- `lib/owl/cli/internal/commands/spec_apply.rb#emit` — JSON payload без `unchanged`.
- `lib/owl/cli/internal/commands/spec_merge.rb` — `json_payload` не выносит
  `unchanged` на верхний уровень; `print_merge` (summary) печатает только
  `merge[:applied]`-counts, без `unchanged`.

# Decision

1. **spec_apply.rb#emit**: добавить `unchanged: value[:unchanged]` в хэш
   `JsonPrinter.success`. Одна строка; `value[:unchanged]` уже есть в результате
   `Api.apply`.
2. **spec_merge.rb#json_payload**: добавить `unchanged: value.dig(:merge,
   :unchanged)` на верхний уровень payload (рядом с `applied`/`merge`). При
   no-op merge (`merge: nil`) `dig` вернёт `nil` — аддитивно и nil-safe.
3. **spec_merge.rb summary**: в `print_merge` (есть `merge`-хэш) добавить вторую
   строку про unchanged, по образцу существующей `delta:`-строки:
   `  unchanged: added A  modified B  removed C` из `merge[:unchanged]`. При
   отсутствии `merge[:unchanged]` — печатать нули (как `delta:` уже делает через
   `.to_i`). Ветка `no_spec_delta` (ранний return) не трогается → при graceful
   no-op unchanged-строка не печатается.

Никаких изменений в `Specs`-движке/Api: только CLI-команды.

# Alternatives

- **Выносить unchanged на верх в spec_merge через распаковку merge целиком.**
  Избыточно; `dig(:merge, :unchanged)` точечно и nil-safe. Выбрано.
- **Печатать unchanged-строку всегда, включая no_spec_delta.** При no-op merge нет
  merge-данных (`merge: nil`) — строка была бы вводящей в заблуждение «added 0…».
  Печатаем только когда есть `merge`-хэш (как `delta:`-строка). Выбрано.
- **Менять API, чтобы merge_task возвращал unchanged на верхнем уровне.** Лишнее
  изменение доменного слоя; CLI и так имеет доступ через `merge`. Отклонено —
  правим только презентацию.

# Risks

- **nil при no-op merge.** `merge: nil` → `print_merge` уже гейтит на
  `merge.is_a?(Hash)`; `json_payload` использует `dig` (nil-safe). Низкий риск.
- **Покрытие.** Тронуты CLI-команды (не `api.rb`) — gate `**/api.rb` не страдает.
  Регрессионные тесты на оба вывода.

# API

- **CLI:** `owl spec apply --json` → payload теперь несёт `unchanged`. `owl spec
  merge --json` → `unchanged` на верхнем уровне (в дополнение к `merge`). `owl
  spec merge --no-json` → дополнительная строка `unchanged: …`. Аддитивно,
  back-compat.
- **Ruby:** правки только в `spec_apply.rb#emit`, `spec_merge.rb#json_payload` и
  `spec_merge.rb#print_merge` (или новый `print_unchanged`). Доменный слой без
  изменений.
