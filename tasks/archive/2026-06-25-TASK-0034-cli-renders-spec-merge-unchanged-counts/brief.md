---
status: approved
summary: "Завершение TASK-0029: счётчики unchanged (идемпотентные no-op'ы) считаются движком, но CLI их не показывает оператору — owl spec apply --json вовсе их не отдаёт, а owl spec merge --no-json summary не печатает. Сделать unchanged видимыми в обоих выводах."
---

# Problem

TASK-0029 сделал spec-merge идемпотентным: движок считает `unchanged:
{added, modified, removed}` (no-op'ы: повторный ADD идентичного / REMOVE
отсутствующего). API (`Specs::Api.apply`/`merge_task`) их возвращает. Но CLI
не доносит их до оператора в двух местах:

1. **`owl spec apply --json`** — payload (`spec_apply.rb#emit`) содержит `applied`,
   но НЕ `unchanged`. Счётчик no-op'ов теряется в JSON-выводе целиком.
2. **`owl spec merge --no-json`** — человекочитаемый summary (`spec_merge.rb#print_merge`)
   печатает только `delta: added X modified Y removed Z` из `merge[:applied]`, но
   не строку про `unchanged`. (В `--json` для merge unchanged доезжает вложенным в
   под-объект `merge`, но на верхнем уровне его нет — оператору приходится копать.)

Итог: оператор/`merge_docs` не видит, сколько изменений было реально применено, а
сколько — идемпотентные no-op'ы. Это снижает наблюдаемость ровно той фичи, ради
которой делался TASK-0029 («honest counts: applied vs unchanged»).

# Goal

Сделать `unchanged`-счётчики видимыми во всех релевантных выводах CLI:
`owl spec apply --json` отдаёт `unchanged`; `owl spec merge --no-json` печатает
строку про unchanged; `owl spec merge --json` выносит `unchanged` на верхний
уровень payload (рядом с applied) для удобства потребителя. Без изменения семантики
merge/apply.

# Scenarios

### Requirement: spec apply --json отдаёт unchanged

The system SHALL include the `unchanged` counts in `owl spec apply --json` output.

#### Scenario: повторный apply показывает no-op в JSON
- WHEN дельта применяется второй раз (всё идемпотентно) через `owl spec apply
  --json`
- THEN JSON содержит `unchanged` с ненулевыми счётчиками (напр. `added: 1`),
  отражая no-op'ы

### Requirement: spec merge --no-json печатает unchanged

The system SHALL print the `unchanged` counts in the `owl spec merge --no-json`
summary.

#### Scenario: summary показывает applied и unchanged
- WHEN выполняется `owl spec merge TASK --no-json` для применённой дельты
- THEN summary содержит строку с `unchanged: added A modified B removed C`
  рядом со строкой `delta: …`

### Requirement: spec merge --json выносит unchanged на верхний уровень

The system SHALL expose `unchanged` at the top level of `owl spec merge --json`.

#### Scenario: unchanged доступен без вложенности
- WHEN выполняется `owl spec merge TASK --json`
- THEN payload содержит `unchanged` на верхнем уровне (в дополнение к
  существующему `merge`/`applied`)

# Edge cases

- **Нулевые счётчики.** Когда no-op'ов нет, `unchanged` = `{added:0, modified:0,
  removed:0}`; печатать/отдавать как есть (нули), для согласованности с `delta:`-строкой.
- **no_spec_delta / no-op merge.** Если merge — graceful no-op (`reason:
  no_spec_delta`/`already_merged`, `merge: nil`), summary остаётся как сейчас
  (не печатать unchanged-строку при отсутствии merge-данных). Не падать на nil.
- **dry-run.** Под `--dry-run` unchanged считается так же (превью), вывод
  согласован.
- **Не менять семантику.** Это только про вывод CLI; движок merge/apply и его
  результаты не трогаем.
- **Back-compat JSON.** Добавление поля `unchanged` — аддитивно, существующие
  потребители не ломаются. patch bump + CHANGELOG.

# Acceptance criteria

- [ ] `owl spec apply --json` payload содержит `unchanged` (из `value[:unchanged]`).
- [ ] `owl spec merge --no-json` summary печатает строку `unchanged: added A
  modified B removed C` (когда есть merge-данные).
- [ ] `owl spec merge --json` отдаёт `unchanged` на верхнем уровне payload.
- [ ] Graceful no-op (merge: nil) и нулевые счётчики обрабатываются без падения.
- [ ] Регрессионные RSpec на каждый вывод; rspec зелёный; 100% покрытие тронутых
  `**/api.rb` (если затронут); RuboCop net-zero; patch bump VERSION + CHANGELOG.
