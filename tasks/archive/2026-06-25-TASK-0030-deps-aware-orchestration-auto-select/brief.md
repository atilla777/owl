---
status: approved
summary: "Deps-aware orchestration auto-select — owl next / claim --next должны выбирать только задачи, чьи blocked_by-зависимости завершены и чей собственный статус не on_hold/blocked/terminal; standalone owl task available остаётся dependency-blind по контракту."
---

# Problem

Оркестратор авто-выбирает задачу через `TaskResolver.auto_select`
(`lib/owl/orchestration/internal/task_resolver.rb`), который зовёт
`Tasks::Api.available` → `AvailabilityScanner`. Этот сканер **dependency-blind by
design** (так сказано в его докстринге): он ранжирует по priority+age и проверяет
только живой claim, но **игнорирует**:

- межзадачные зависимости `blocked_by` (P1-B deps-DAG, TASK-0026) — авто-выбор может
  предложить задачу, заблокированную незавершённой зависимостью;
- task-level `status` (P1-A, TASK-0025) — `on_hold`/`blocked`/`done` задача всё равно
  может быть авто-выбрана.

При этом deps+status-aware сканер уже существует: `Tasks::Api.ready` →
`ReadyScanner` (TASK-0026), и он сортирует **идентично** AvailabilityScanner
(`[-priority, created_at, id]`). То есть фичи P1 есть в данных, но оркестратор их не
учитывает при авто-выборе — `owl next` без текущего указателя и `claim --next` могут
посоветовать dep-заблокированную или отложенную задачу.

# Goal

Сделать авто-выбор оркестратора deps+status-aware: переключить хвост `auto_select`
на готовый ready-набор (`ReadyScanner`), чтобы `owl next` / `owl instructions` /
`claim --next` никогда не предлагали задачу с незавершёнными `blocked_by` или со
статусом `on_hold`/`blocked`/terminal. Standalone-команда `owl task available`
**остаётся** dependency-blind, как обещает её докстринг (back-compat).

# Scenarios

### Requirement: авто-выбор оркестратора исключает заблокированные задачи

The system SHALL exclude tasks with incomplete `blocked_by` dependencies from
orchestrator auto-selection.

#### Scenario: dep-заблокированная задача не авто-выбирается
- WHEN нет текущего указателя, и задача B имеет `blocked_by: [A]`, где A не
  done/archived, а B — единственная незаклеймленная задача с высшим приоритетом
- THEN `owl next` / `TaskResolver.resolve` НЕ выбирает B (source становится `none`,
  если других готовых задач нет)
- AND после того как A переходит в `done`/`archived`, B становится авто-выбираемой

### Requirement: авто-выбор оркестратора исключает нерабочие статусы

The system SHALL exclude tasks whose own status is `on_hold`, `blocked`, or terminal
from orchestrator auto-selection.

#### Scenario: on_hold задача не авто-выбирается
- WHEN нет текущего указателя, и задача с высшим приоритетом имеет `status: on_hold`
- THEN авто-выбор её пропускает и берёт следующую готовую задачу (или `none`)

### Requirement: standalone available сохраняет dependency-blind контракт

The system SHALL keep `owl task available` dependency-blind for backward
compatibility.

#### Scenario: available по-прежнему возвращает dep-заблокированную задачу
- WHEN вызывается `owl task available --json` при наличии dep-заблокированной задачи
- THEN она присутствует в выдаче `available` (поведение и docstring не меняются)

# Edge cases

- **Идентичная сортировка.** `ReadyScanner` и `AvailabilityScanner` сортируют
  одинаково (`[-priority, created_at, id]`), поэтому порядок авто-выбора не меняется
  для незаблокированных задач — меняется только фильтрация.
- **`ready ⊆ available`.** ReadyScanner строго уже: добавляет фильтр deps + terminal
  status поверх той же claim-проверки. Переключение auto_select на ready не может
  «расширить» набор.
- **explicit / current_pointer не трогаем.** Меняется только хвост `auto_select`;
  явный TASK-ID и current-указатель резолвятся как раньше (пользователь вправе вести
  заблокированную задачу вручную).
- **reason.** Авто-выбор сохраняет осмысленный `reason` (priority-based), эквивалентный
  текущему; consumer-формат resolution `{ task_id, source: 'auto_select', reason }`
  не ломается.
- **Пустой ready-набор.** Если ready пуст → `none_resolution` (как сейчас при пустом
  available) — `owl next` остаётся read-only, ничего не мутирует.
- **Версионирование.** Изменение поведения оркестратора — minor bump `Owl::VERSION` +
  запись в `CHANGELOG.md` в том же коммите.

# Acceptance criteria

- [ ] `TaskResolver.auto_select` использует deps+status-aware ready-набор
  (`Tasks::Api.ready` / `ReadyScanner`) вместо dependency-blind `available`.
- [ ] `owl next` / `owl instructions` / `claim --next` без current-указателя не
  предлагают задачу с незавершёнными `blocked_by` или статусом
  `on_hold`/`blocked`/terminal.
- [ ] `owl task available` остаётся dependency-blind (поведение и docstring
  неизменны; регрессионный тест это подтверждает).
- [ ] Порядок авто-выбора незаблокированных задач не меняется (та же сортировка).
- [ ] explicit TASK-ID и current-pointer резолюция не затронуты.
- [ ] Регрессионные RSpec на каждый сценарий; 100% покрытие затронутых `**/api.rb`;
  RuboCop net-zero; minor bump VERSION + CHANGELOG.
