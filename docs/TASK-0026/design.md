---
status: shipped
summary: "Модель межзадачного DAG: blocked_by[] каноничен, blocks вычисляется; dep add/rm с ацикличностью через graph_builder; owl task ready по индексу; интеграция с available/next отложена."
---

# Context

P1-B строит dependency-aware ведение работ поверх P1-A (status/index). Переиспользует
locked `IndexWriter` (TASK-0021), `schemas/task.json` (TASK-0025) и cycle-detection из
`workflows/internal/graph_builder.rb`.

# Decision

1. **Каноничное ребро `blocked_by: []`** в `task.yaml` (список id задач, которые должны
   завершиться раньше данной). Обратные рёбра (`blocks`/dependents) НЕ хранятся —
   вычисляются обратным сканом индекса при необходимости (избегаем рассинхрона).

2. **CLI `owl task dep`:**
   - `owl task dep add TASK --on DEP` → добавляет `DEP` в `TASK.blocked_by`.
   - `owl task dep rm TASK --on DEP` → удаляет (no-op если нет).
   - `owl task dep list TASK [--json]` → `{blocked_by: [...], blocks: [...]}` (blocks —
     вычисленные dependents).
   Семантика «--on» = «зависит от» (понятнее, чем позиционные A/B).

3. **Валидации dep add:**
   - **Self-dep** (`TASK --on TASK`) → ошибка `self_dependency`.
   - **Несуществующий DEP/TASK** → ошибка `task_not_found`.
   - **Ацикличность**: построить временный граф `blocked_by`-рёбер по индексу + новое
     ребро, прогнать `detect_cycle` (переиспользуя логику `GraphBuilder`); цикл →
     ошибка `dependency_cycle` с путём.

4. **`owl task ready [--json]`** возвращает задачи, для которых выполнено ВСЁ:
   - все id из `blocked_by` имеют терминальный статус (`done` ИЛИ `archived`;
     архивированная задача = завершённая зависимость);
   - задача не заклеймлена (нет живого lease);
   - собственный статус не терминальный (`done`/`archived`/`abandoned`).
   Работает по индексу (несёт `blocked_by` + `status`); сортировка как `available`
   (priority desc, затем age).

5. **Index расширение.** `build_index_entry` добавляет `blocked_by` в index-entry;
   запись — через locked `IndexWriter`. Терминальность зависимости определяется по
   `status` зависимой записи в индексе (для архивных — статус `archived`).

6. **Граница scope (явно):** `owl task available`/`owl next`/auto-claim в этой задаче
   НЕ становятся dep-aware — `ready` отдельная команда. Интеграция (чтобы оркестратор
   автоматически пропускал заблокированные) — follow-up workflow-интеграции (как в
   P1-A отложили влияние on_hold/blocked на auto-claim). Это ограничивает blast radius
   оркестратора.

7. **Обратная совместимость.** Legacy `task.yaml` без `blocked_by` → `[]`; schema-поле
   опционально, `additionalProperties: true` сохраняется.

# Alternatives

- **Хранить и `blocks`, и `blocked_by`** (двунаправленно). Отвергнуто: дублирование →
  риск рассинхрона; обратные рёбра дёшево вычислить сканом индекса.
- **Сразу интегрировать deps в `available`/`next`.** Отложено: меняет поведение
  оркестратора (риск), требует отдельного решения; `ready` достаточно для v1.
- **Позиционные `dep add A B`.** Отвергнуто в пользу `--on` (явная семантика «зависит
  от», меньше путаницы про направление).

# Risks

- **Стоимость cycle-check.** Граф строится по индексу (O(V+E)); для текущих масштабов
  дёшево. Документировать, что check — на запись, не на чтение.
- **Висячие ссылки.** Если зависимая задача удалена (`task delete`) — `blocked_by`
  может указывать на несуществующую. Решение: `task delete` чистит обратные ссылки ИЛИ
  `ready` трактует несуществующую dep как завершённую (выбрать в impl: чистить ссылки
  предпочтительнее; минимум — не падать). Зафиксировать в плане.
- **Покрытие `tasks/api.rb`.** Новые ветки покрыть до 100%.

# API

CLI (`{ok, value|error}`):
- `owl task dep add TASK --on DEP` → `{ok, task_id, blocked_by:[...]}`; ошибки
  `self_dependency` / `task_not_found` / `dependency_cycle`.
- `owl task dep rm TASK --on DEP` → `{ok, task_id, blocked_by:[...]}`.
- `owl task dep list TASK` → `{ok, blocked_by:[...], blocks:[...]}`.
- `owl task ready [--json]` → `{ok, ready:[index-entry...]}`.

Ruby (`Owl::Tasks::Api`): `add_dependency/remove_dependency(root:, task_id:, depends_on:)`,
`dependencies(root:, task_id:)`, `ready(root:)` → `Owl::Result`. Cycle-check
переиспользует `Owl::Workflows::Internal::GraphBuilder.detect_cycle` (или вынести общий
helper, если связывание неудобно). Index-entry билдер дополняется `blocked_by`.
