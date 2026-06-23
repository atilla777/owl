---
status: approved
summary: >-
  Починить composite children_complete-gate, который намертво заклинивает, когда
  единственный/последний ребёнок самоархивируется (`owl archive CHILD`): ребёнок
  пропадает из активного индекса, ChildrenLister видит пустой набор, и
  aggregate_state возвращает 'open' навсегда — родительские archive/commit_push
  не открываются. Фикс: ChildrenLister/aggregate учитывают и АРХИВНЫХ детей (по
  parent_id в archive-роли), так что полностью архивный ребёнок даёт state
  'archived' → aggregate 'done' → гейт открывается. Родитель «без детей вообще»
  по-прежнему 'open' (ложного открытия нет). Плюс одноразовая реконсиляция уже
  застрявшего TASK-0015 (закрыть его archive/commit_push после фикса).
---

# Brief — Composite gate bug: child self-archive wedges parent children_complete gate

## Problem

В `composite_feature` шаги родителя `archive`/`commit_push` несут
`gate: children_complete`: они не появляются в `ready-steps`, пока
`aggregate-status.aggregate ∈ {ready, done}`. Но aggregate вычисляется из
АКТИВНОГО индекса:

- `Owl::Tasks::Internal::ChildrenLister.call` читает `tasks/index.yaml` и
  выбирает записи с `parent_id == PARENT`.
- `owl archive CHILD` (ровно то, что советует контекст шага `archive`:
  «Drive this step with `owl archive TASK-ID --json`») физически переносит
  ребёнка в `tasks/archive/` и **убирает его из индекса**.
- После этого `ChildrenLister` возвращает пустой список, а
  `AggregateStatus.aggregate_state` имеет `return 'open' if by_child.empty?`
  (`lib/owl/tasks/internal/aggregate_status.rb:67`). → aggregate `'open'`
  навсегда, гейт `children_complete` не открывается, родительские
  `archive`/`commit_push` залипают в `blocked_by_children`/`pending`.
- `owl task index rebuild` не помогает: сканирует только прямых детей `tasks/`,
  не `tasks/archive/**`.
- Прямой `owl archive PARENT` обходит гейт и архивирует родителя физически, но
  bookkeeping шагов остаётся незакрытым.

Связь сохраняется, но не видна: архивный `task.yaml` ребёнка содержит
`parent_id: TASK-0015` (подтверждено), однако ни `ChildrenLister`, ни
`owl archive list/show` не выставляют parent_id наружу.

**Реальный инцидент:** TASK-0015 (родитель `owl recall`) сейчас физически
заархивирован, ребёнок TASK-0018 завершён и заархивирован, но у TASK-0015
`archive: blocked_by_children`, `commit_push: pending` — застрял из-за этого
бага.

## Goal

1. **Фикс root cause:** `ChildrenLister`/aggregate учитывают и архивных детей
   (найденных по `parent_id` в archive-роли), не только активный индекс.
   Полностью архивный ребёнок → child-state `archived`; родитель, все дети
   которого `archived`, → aggregate `done` → гейт `children_complete`
   открывается, `archive`/`commit_push` становятся ready.
2. **Без ложных открытий:** родитель, у которого детей не было вовсе (или
   `decompose` не порождал детей), остаётся `aggregate: open` — пустой набор
   по-прежнему не открывает гейт. Различать «детей не было» и «дети были, но
   все архивны».
3. **Реконсиляция TASK-0015** (одноразовая, как часть поставки): после фикса
   его aggregate станет `done`; довести `archive`/`commit_push` шаги до `done`,
   чтобы bookkeeping сошёлся и задача была закрыта чисто.

### Не входит в объём (Non-goals)

- Менять lifecycle ребёнка / запрещать `owl archive CHILD` (выбран fix-forward
  «aggregate видит архив», а не превенция self-archive).
- Менять формат `task.yaml`, JSON-контракт `aggregate-status`/`ready-steps`
  (форма та же; набор `by_child` лишь становится полнее).
- Атомарный родительский subtree-archive переписывать.
- Кросс-репо / производительность больших архивов сверх разумного (отметить как
  риск).

## Scenarios

### Requirement: архивные дети учитываются в aggregate

The system SHALL включать архивных детей композитного родителя (найденных по
`parent_id` в archive-роли) в расчёт `aggregate-status`, присваивая им state
`archived`.

#### Scenario: последний ребёнок самоархивировался — гейт открывается
- WHEN у композитного родителя ровно один ребёнок, и он заархивирован
  (`owl archive CHILD`), пропав из активного индекса
- THEN `owl task aggregate-status PARENT` возвращает `aggregate: done`,
  `by_child` содержит этого ребёнка со state `archived`
- AND `owl task ready-steps PARENT` показывает `archive` как ready (гейт открыт)
- TEST: spec/owl/tasks/aggregate_status_archived_children_spec.rb

#### Scenario: смешанные дети
- WHEN часть детей активна (`in_progress`), часть архивна
- THEN aggregate не `done` (есть незавершённые), но архивные дети присутствуют в
  `by_child` со state `archived`
- TEST: spec/owl/tasks/aggregate_status_archived_children_spec.rb

### Requirement: нет ложного открытия для бездетного родителя

The system SHALL оставлять `aggregate: open` для композитного родителя, у
которого нет детей ни в индексе, ни в архиве.

#### Scenario: родитель без детей не открывает гейт
- WHEN у композитного родителя нет детей вообще
- THEN `aggregate: open`, гейт `children_complete` закрыт, `archive` не ready
- TEST: spec/owl/tasks/aggregate_status_archived_children_spec.rb

### Requirement: реконсиляция застрявшего TASK-0015

The system SHALL довести TASK-0015 до консистентного завершённого состояния
после фикса.

#### Scenario: TASK-0015 закрыт
- WHEN фикс применён и aggregate TASK-0015 = `done`
- THEN его шаги `archive` и `commit_push` доведены до `done`
- AND итоговое состояние задачи консистентно (нет залипших pending-шагов)
- TEST: ручная проверка `owl status TASK-0015` после реконсиляции (одноразовая
  операция, фиксируется в verification)

## Edge cases

- **Родитель и сам архивен** (как TASK-0015): aggregate всё равно корректно
  считает архивных детей.
- **Дубль id** ребёнка в индексе и архиве (теоретически): дедуп по `task_id`,
  предпочесть терминальное (archived) состояние.
- **Архивный ребёнок без читаемого `parent_id`** (старый формат) → не считается
  ребёнком этого родителя; не падать.
- **Производительность:** скан archive-роли по `parent_id` на каждый
  aggregate-вызов; на текущем масштабе (десятки задач) дёшево — отметить как
  возможную будущую оптимизацию (индексация архива).
- **Не-composite задачи**: поведение не меняется (aggregate — только для
  composite).
- **Реконсиляция TASK-0015** должна быть идемпотентна/безопасна (если шаги уже
  закрыты — no-op).

## Acceptance criteria

1. `ChildrenLister`/aggregate учитывают архивных детей по `parent_id` в
   archive-роли; архивный ребёнок → state `archived` в `by_child`.
2. Композитный родитель, все дети которого архивны, → `aggregate: done` →
   гейт `children_complete` открыт (`archive`/`commit_push` ready). Воспроизведён
   и закрыт исходный wedge (ребёнок самоархивировался → гейт открывается).
3. Родитель без детей (в индексе и архиве) → `aggregate: open` (ложного
   открытия нет).
4. Регрессионный spec на сценарий-wedge и на бездетного родителя; полный
   `bundle exec rspec` зелёный (0 failures), rubocop чист.
5. JSON-контракт `aggregate-status`/`ready-steps` по форме не изменён (лишь
   полнее `by_child`); не-composite поведение не затронуто.
6. TASK-0015 реконсилирован: `archive`/`commit_push` доведены до `done`,
   состояние консистентно (зафиксировать в verification).
7. Если тронут `lib/**` — бамп `Owl::VERSION` (patch: back-compat багфикс
   readiness-движка, контракт не сломан) + запись в `CHANGELOG.md` тем же
   коммитом (Конституция §7.1). 100% покрытие затронутых `**/api.rb`.
8. Edge cases выше либо покрыты, либо явно зафиксированы как ограничения.
