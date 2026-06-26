---
status: approved
summary: >-
  Терминальные задачи (abandoned/archived/done) больше не «протекают» в
  оркестрацию: abandon чистит current-указатель, явный доступ к терминальной
  задаче через next/ready-steps/status/instructions — структурная ошибка,
  `owl next` по терминальному указателю тихо проваливается в auto_select, а
  понятие TERMINAL_STATUSES сводится к одному общему источнику истины.
---

# Problem

Терминальный статус задачи (`abandoned` / `archived` / `done`) сегодня не
защищён единообразно, и мёртвая задача «протекает» в оркестрацию.

Наблюдаемый случай (воспроизведён в этой сессии): TASK-0042 имеет
`status: abandoned`, но:

- `abandon` снял claim, но **не очистил** current-указатель
  (`.owl/local/current.yaml`), поэтому указатель остался висеть на мёртвой
  задаче;
- `owl next` без аргумента разрешил задачу через current-указатель
  (`TaskResolver.from_current`) **без проверки терминального статуса** и
  выдал `dispatch_step plan` — то есть посоветовал работать по abandoned-задаче.

Сопутствующие дефекты:

- `AbandonWriter` (`lib/owl/tasks/internal/abandon_writer.rb`) не использует
  `Archive::CurrentResetter.reset_if_matches`, хотя `Deleter` уже делает это
  с TASK-0041 — поведение abandon и delete относительно указателя разошлось.
- Понятие «терминальный статус задачи» продублировано минимум в двух местах с
  расходящимся порядком и составом: `availability_scanner.rb`
  (`%w[archived abandoned done]`) и `ready_scanner.rb`
  (`%w[done archived abandoned]`). Отдельный шаговый `TERMINAL_STATUSES`
  (`%w[done skipped]`) в `archive/completion_gate.rb` — про статусы шагов, это
  другое понятие и в объединение НЕ входит.
- Команды `next` / `ready-steps` / `status` / `instructions`, вызванные с явным
  терминальным TASK-ID, не отвергают его структурной ошибкой, а ведут себя так,
  будто задача жива.

# Goal

Сделать терминальный статус задачи единообразно безопасным:

1. `abandon` очищает current-указатель, если он указывал на эту задачу
   (паритет с `delete`).
2. Явный доступ к терминальной задаче через `next` / `ready-steps` / `status` /
   `instructions` возвращает структурную ошибку `task_terminal` (а не делает вид,
   что задача исполнима).
3. `owl next` **без** явного TASK-ID, разрешая задачу из current-указателя,
   трактует терминальный указатель как «нет текущей задачи» и проваливается в
   `auto_select` (тихий fallback, без ошибки).
4. Понятие терминального статуса задачи сведено к одному общему
   `TERMINAL_STATUSES` (один источник истины), переиспользуемому
   `availability_scanner` и `ready_scanner`.

Изменение целиком внутреннее (CLI/оркестрация Owl), без эффекта для конечного
пользователя продукта — выгода в надёжности самого Owl.

# Scenarios

### Requirement: abandon clears the current pointer

The system SHALL clear the current-task pointer when a task is abandoned and the
pointer named that task.

#### Scenario: abandon of the current task drops the pointer
- WHEN `owl task abandon TASK-X` выполняется для задачи, на которую указывает
  current-указатель
- THEN указатель `.owl/local/current.yaml` удаляется
- AND последующий `owl task current` сообщает `no_current_task`, а не ведёт на
  abandoned-задачу

#### Scenario: abandon of a non-current task leaves the pointer intact
- WHEN `owl task abandon TASK-X`, а current-указатель ведёт на другую задачу TASK-Y
- THEN указатель остаётся на TASK-Y без изменений

### Requirement: explicit access to a terminal task is rejected

The system SHALL return a structured `task_terminal` error when `next`,
`ready-steps`, `status`, or `instructions` is invoked with an explicit TASK-ID
whose status is terminal (`abandoned` / `archived` / `done`).

#### Scenario: explicit next on a terminal task errors
- WHEN `owl next TASK-X --json` вызван с явным id, а TASK-X в статусе `abandoned`
- THEN команда возвращает `ok: false` с кодом ошибки `task_terminal`
- AND не возвращает `dispatch_step` и не предлагает другую задачу

#### Scenario: explicit status/ready-steps/instructions on a terminal task error
- WHEN `owl status TASK-X`, `owl task ready-steps TASK-X` или
  `owl instructions TASK-X` вызваны с явным терминальным id
- THEN каждая команда возвращает `ok: false` с кодом `task_terminal`

### Requirement: next falls through a terminal current pointer

The system SHALL treat a terminal current-pointer as "no current task" and fall
through to auto-select when `owl next` is invoked without an explicit TASK-ID.

#### Scenario: next without arg ignores a stale terminal pointer
- WHEN current-указатель ведёт на терминальную задачу (legacy/archived) и
  `owl next --json` вызван без аргумента
- THEN ладдер игнорирует терминальный указатель и выбирает следующую доступную
  задачу через `auto_select`
- AND при наличии доступной задачи возвращает её `dispatch_step`, а при
  отсутствии — `no_available_task` (но не `dispatch_step` по терминальной)

### Requirement: single source of truth for terminal task statuses

The system SHALL expose one shared `TERMINAL_STATUSES` constant for task-level
terminal statuses, reused by the availability and ready scanners.

#### Scenario: scanners reuse the shared constant
- WHEN `availability_scanner` и `ready_scanner` фильтруют задачи по терминальному
  статусу
- THEN оба читают один общий `TERMINAL_STATUSES` (`archived` / `abandoned` /
  `done`), а не свои локальные копии
- AND шаговый `completion_gate` `TERMINAL_STATUSES` (`done` / `skipped`) остаётся
  отдельным понятием и не объединяется с задачным

# Edge cases

- **Идемпотентный abandon.** Повторный `owl task abandon TASK-X` по уже
  abandoned-задаче (ранний idempotent-возврат в `AbandonWriter.locked_call`)
  всё равно должен гарантировать, что указатель очищен, если он на неё указывал.
- **Чужой указатель.** `CurrentResetter.reset_if_matches` уже проверяет
  совпадение id — abandon не должен трогать указатель, ведущий на другую задачу.
- **Многосессионность.** Очистка указателя — локальное per-clone состояние
  (`.owl/local/`), не общее; гонок с другими клонами не вносит.
- **`archived` vs `abandoned` vs `done`.** Все три считаются терминальными для
  задачного `TERMINAL_STATUSES`; `done` уже входит в оба нынешних списка, состав
  объединённой константы не меняется.
- **Явный vs неявный резолв в `next`.** Различие проводится по источнику id:
  явно переданный флагом `TASK-ID` → reject; id, взятый из current-указателя →
  fallback. `instructions`/`status`/`ready-steps` работают с явным id, поэтому
  для них применяется reject.
- **Шаговые терминальные статусы.** Объединение касается ТОЛЬКО задачного
  понятия; `completion_gate`/архивные шаговые проверки не трогаются, чтобы не
  сломать гейт архивации.

# Acceptance criteria

- [ ] `owl task abandon TASK-X` очищает current-указатель, если он указывал на
      TASK-X, и не трогает его в противном случае; покрыто проверкой паритета с
      `delete` (переиспользование `Archive::CurrentResetter.reset_if_matches` в
      `AbandonWriter`).
- [ ] `owl next TASK-X` / `owl status TASK-X` / `owl task ready-steps TASK-X` /
      `owl instructions TASK-X` с явным терминальным id возвращают `ok: false`
      с кодом `task_terminal` и корректным CLI exit-кодом.
- [ ] `owl next` без аргумента при терминальном current-указателе не возвращает
      `dispatch_step` по терминальной задаче, а проваливается в `auto_select`
      (или `no_available_task`, если доступных нет).
- [ ] Введён единый `TERMINAL_STATUSES` для задачного уровня; `availability_scanner`
      и `ready_scanner` читают его, локальные дубликаты удалены; шаговый
      `completion_gate` остаётся отдельным.
- [ ] Изменения проходят через `bin/owl`/слои Backend/Internal/Api без прямого
      доступа к FS из верхних слоёв (см. `docs/agents/27_*`).
- [ ] Добавлены RSpec-тесты на каждый сценарий; затронутые `lib/owl/**/api.rb`
      сохраняют 100% покрытие строк (см. `docs/agents/30_*`).
- [ ] `Owl::VERSION` поднят и добавлена запись в `CHANGELOG.md` (поведенческое
      изменение CLI; новый код ошибки `task_terminal` — потенциально мажорное для
      JSON-контракта, уточняется на шаге design/plan).
