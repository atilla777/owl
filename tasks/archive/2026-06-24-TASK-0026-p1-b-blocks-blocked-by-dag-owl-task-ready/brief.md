---
status: approved
summary: "Межзадачные зависимости (blocked_by DAG) + owl task ready — задача готова, когда все её зависимости завершены; основа dependency-aware ведения работ (beads-паритет)."
---

# Problem

P1-A дал статусы/labels/query. Но у Owl всё ещё нет **межзадачных зависимостей**: связь
только parent/child (composite). Нельзя выразить «TASK-B нельзя начинать, пока не
завершён TASK-A», нет dependency-aware «что готово к работе» (ядро beads — `bd ready`).
`owl task available` ранжирует по priority+age, но не учитывает блокировки между
независимыми задачами.

# Goal

Ввести межзадачный DAG зависимостей (`blocked_by`) с проверкой ацикличности и команду
`owl task ready`, возвращающую задачи, у которых все зависимости завершены и которые
можно брать в работу — не ломая существующую parent/child и orchestrator-механику.

# Scenarios

### Requirement: Между задачами можно объявлять зависимости

#### Scenario: добавить зависимость
- WHEN пользователь выполняет `owl task dep add TASK-B --on TASK-A`
- THEN `TASK-B.blocked_by` содержит `TASK-A`; хранится в `task.yaml`/index

#### Scenario: цикл отклоняется
- WHEN добавление зависимости создало бы цикл (напр. A on B, затем B on A)
- THEN операция отклоняется с понятной ошибкой (cycle), граф остаётся ацикличным

#### Scenario: убрать зависимость
- WHEN пользователь выполняет `owl task dep rm TASK-B --on TASK-A`
- THEN связь удаляется; повтор/несуществующая связь — чистый no-op

### Requirement: owl task ready возвращает разблокированные задачи

#### Scenario: задача готова, когда зависимости завершены
- WHEN все задачи из `TASK-B.blocked_by` имеют терминальный статус (`done`/`archived`)
  И TASK-B не заклеймлена И её статус не терминальный
- THEN `owl task ready` включает TASK-B

#### Scenario: задача с незавершённой зависимостью не готова
- WHEN хотя бы одна зависимость из `blocked_by` ещё не завершена
- THEN `owl task ready` НЕ включает TASK-B (она заблокирована)

# Edge cases

- **Каноничное хранение.** Хранить `blocked_by: []` в `task.yaml` (что блокирует данную
  задачу). Обратные рёбра (`blocks`/dependents) вычислять на чтении/при необходимости,
  не дублируя источник истины.
- **Ацикличность.** Переиспользовать cycle-detection из
  `workflows/internal/graph_builder.rb` (`detect_cycle`) — не изобретать.
- **Несуществующие/архивные deps.** `dep add` на несуществующую задачу → понятная
  ошибка. Зависимость на уже архивированную задачу считается завершённой (терминал).
- **Self-dep.** `dep add TASK-A --on TASK-A` отклоняется.
- **Интеграция с available/next (scope-граница).** В v1 `owl task ready` — отдельная
  dependency-aware команда. Влияние deps на `owl task available`/`owl next`/auto-claim
  оставить как явное решение workflow-интеграции (флаг follow-up), чтобы не менять blast
  radius оркестратора в этой задаче. Зафиксировать в design.
- **Index.** Записи индекса несут `blocked_by` (через locked `IndexWriter`), чтобы
  `ready` работал по индексу.
- **Покрытие/версия.** 100% на затронутых `**/api.rb`; minor bump + CHANGELOG.

# Acceptance criteria

- [ ] `task.yaml` поддерживает `blocked_by: []`; `schemas/task.json` расширен.
- [ ] `owl task dep add TASK --on DEP` / `dep rm TASK --on DEP` с проверкой
  ацикличности (переиспользуя graph_builder), self-dep и несуществующих deps.
- [ ] `owl task ready [--json]` возвращает задачи, у которых все `blocked_by`
  терминальны, не заклеймлены и не терминальны сами.
- [ ] `tasks/index.yaml` несёт `blocked_by`; запись через locked `IndexWriter`.
- [ ] Тесты: dep add/rm/cycle/self/ready-разблокировка/ready-блокировка/архивная-dep.
- [ ] `bundle exec rspec` зелёный; 100% покрытие затронутых `**/api.rb`; RuboCop net-zero.
- [ ] `Owl::VERSION` поднят + CHANGELOG.

# Out of scope

- Влияние deps на `owl task available`/`next`/auto-claim (workflow-интеграция,
  follow-up).
- Поиск по активным задачам (TASK-0027). assignees/due/epics.
- Прочие типы связей (relates/duplicates) — при необходимости позже.
