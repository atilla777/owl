---
status: approved
summary: "Дать задачам first-class трекер-метаданные (explicit status + labels), формальную schemas/task.json и owl task query с фильтрами — первый шаг к beads-паритету по ведению списка задач."
---

# Problem

Owl — сильный workflow-движок, но слабый трекер. `task.yaml` хранит только
`id/title/workflow/kind/parent_id/priority/created_at/steps/artifacts`. Нет:
- task-level **статуса** (есть лишь step-статусы; нельзя пометить задачу
  `blocked`/`on_hold`/`in_progress` на уровне задачи);
- **labels/тегов** для группировки и фильтрации;
- **формальной схемы** `task.yaml` (валидации структуры нет — только уникальность id);
- **query/фильтра**: `owl task list` отдаёт всё, нельзя выбрать по статусу/метке/
  приоритету/родителю/workflow.

Из-за этого нельзя «гибко вести список задач» — то, что у beads ядро продукта.

# Goal

Ввести first-class трекер-метаданные задачи (explicit `status` + `labels`),
формальную `schemas/task.json`, и `owl task query` с фильтрами — не ломая существующую
workflow-механику и оставаясь upgrade-safe.

# Scenarios

### Requirement: Задача имеет explicit task-level статус

#### Scenario: установить и прочитать статус задачи
- WHEN пользователь выполняет `owl task set-status TASK-ID on_hold`
- THEN `task.yaml`/index хранит `status: on_hold`, и `owl status`/`owl task query`
  отражают его; статус ортогонален прогрессу шагов

#### Scenario: дефолт и архивация
- WHEN задача создаётся
- THEN её `status` по умолчанию `open`; при `owl archive` статус становится `archived`
  (сохраняется текущее поведение)

### Requirement: Задача имеет labels

#### Scenario: добавить/убрать label
- WHEN пользователь выполняет `owl task label add TASK-ID backend` и затем
  `owl task label rm TASK-ID backend`
- THEN `labels` в `task.yaml`/index обновляется соответственно; дубликаты не плодятся

### Requirement: Список задач фильтруется

#### Scenario: query по статусу и метке
- WHEN пользователь выполняет `owl task query --status open --label backend --json`
- THEN возвращаются только задачи с `status=open` И меткой `backend`; фильтры
  комбинируются (AND); поддержаны также `--priority`, `--parent`, `--workflow`

### Requirement: task.yaml валидируется по схеме

#### Scenario: невалидный статус отклоняется
- WHEN мутация пытается выставить `status` вне допустимого множества
- THEN операция возвращает понятную ошибку валидации (по `schemas/task.json`), а не
  молча пишет мусор

# Edge cases

- **Множество статусов.** `open | in_progress | blocked | on_hold | done | archived`.
  Зафиксировать в design; `archived` ставится системно при archive.
- **Обратная совместимость.** Старые `task.yaml` без `status`/`labels` читаются как
  `status: open`, `labels: []` (миграция «по чтению», без принудительного rewrite);
  index rebuild добавляет поля.
- **Index расширение.** Записи `tasks/index.yaml` несут `status` и `labels`, чтобы
  query работал по индексу без чтения каждого task.yaml. Запись — через
  существующий locked `IndexWriter` (TASK-0021).
- **Схема additive.** `schemas/task.json` описывает текущие + новые поля;
  `additionalProperties` — осознанно (не ломать неизвестные будущие поля).
- **Покрытие.** Изменения в `lib/owl/tasks/api.rb` требуют 100% покрытия.
- **Версионирование.** Новые поля + CLI — minor bump `Owl::VERSION` + CHANGELOG.

# Acceptance criteria

- [ ] `task.yaml` поддерживает `status` (enum) и `labels: []`; дефолты `open`/`[]`;
  обратная совместимость со старыми файлами.
- [ ] `owl task set-status`, `owl task label add|rm` — мутаторы с валидацией.
- [ ] `schemas/task.json` + валидация task.yaml на мутациях.
- [ ] `owl task query --status --label --priority --parent --workflow --json` —
  комбинируемые AND-фильтры по индексу.
- [ ] `tasks/index.yaml` несёт `status`+`labels`; запись через locked `IndexWriter`.
- [ ] Тесты на статус/labels/query/схему/обратную совместимость.
- [ ] `bundle exec rspec` зелёный; 100% покрытие затронутых `**/api.rb`; RuboCop
  net-zero.
- [ ] `Owl::VERSION` поднят + CHANGELOG.

# Out of scope

- Межзадачные зависимости (blocks/blocked-by DAG) + `owl task ready` — TASK-0026.
- Поиск по активным задачам (`recall --scope`) — TASK-0027.
- assignees/due dates/epics — последующие итерации при необходимости.
