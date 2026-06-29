---
status: approved
summary: >-
  step skip и task abandon оставляют осиротевший per-task active-step lock,
  а step reset не может снять lock с non-running шага (заставляет
  step start --force). Фикс: skip/abandon чистят lock (по match'у), reset
  получает recovery-снятие stale-lock даже для non-running шага.
---

# Problem

Per-task active-step lock (`.owl/local/active_steps/<TASK-ID>.yaml`) пишется в
`owl step start` и снимается только в `owl step complete` и `owl step reset`
(оба зовут `Steps::Api.active_step_lock_clear` по match'у шага). Три пути
оставляют lock осиротевшим:

1. **`owl step skip`** (`lib/owl/cli/internal/commands/step_skip.rb`) переводит
   шаг в `status: skipped` через `Steps::Api.skip`, но **никогда** не чистит
   active-step lock. Если skip применён к *running*-шагу, lock остаётся, и
   следующий `owl step start` для этой задачи падает с `active_step_locked`.
2. **`owl task abandon`** (`Tasks::Api.abandon`) не трогает active-step lock
   задачи: брошенная задача с running-шагом тоже оставляет lock.
3. **`owl step reset`** (`Steps::Api.reset`) жёстко проверяет
   `unless current == 'running'` и возвращает `step_not_running` для любого
   не-running статуса. Поэтому штатным способом (`reset`) снять *stale*-lock,
   когда шаг уже `skipped`/`pending`/`done`, нельзя — оператор вынужден делать
   тяжёлый `owl step start --force`, который молча перетирает in-flight шаг.

Итог: операторские/оркестраторские потоки, использующие `skip`/`abandon`,
оставляют задачу в состоянии, из которого нет чистого штатного выхода.

# Goal

`owl step skip` и `owl task abandon` НЕ должны оставлять осиротевший
active-step lock, а `owl step reset` должен уметь снять stale-lock даже когда
целевой шаг не в статусе `running` — без обращения к `step start --force`.

# Scenarios

### Requirement: skip снимает свой active-step lock

The system SHALL clear the per-task active-step lock when `owl step skip`
skips the step that currently holds the lock.

#### Scenario: skip running-шага с активным lock'ом
- WHEN шаг находится в `status: running` и для задачи существует active-step
  lock, указывающий на этот шаг, и выполняется `owl step skip TASK STEP --reason ...`
- THEN шаг переходит в `status: skipped`
- AND active-step lock задачи снимается (lock-файл удалён)
- AND последующий `owl step start TASK NEXT_STEP` не падает с `active_step_locked`

#### Scenario: skip шага, не владеющего lock'ом, не трогает чужой lock
- WHEN active-step lock задачи указывает на ДРУГОЙ шаг, и выполняется
  `owl step skip TASK STEP --reason ...` для шага без lock'а
- THEN существующий lock другого шага остаётся нетронутым

### Requirement: abandon снимает active-step lock задачи

The system SHALL clear the per-task active-step lock when `owl task abandon`
abandons a task that has a running step holding the lock.

#### Scenario: abandon задачи с running-шагом
- WHEN задача имеет шаг в `status: running` и существует active-step lock для
  этой задачи, и выполняется `owl task abandon TASK`
- THEN задача переходит в abandoned-состояние
- AND active-step lock задачи снимается

### Requirement: reset снимает stale-lock для non-running шага

The system SHALL allow `owl step reset` to clear a stale active-step lock that
refers to the target step even when that step is not in `status: running`.

#### Scenario: reset stale-lock после skip (recovery)
- WHEN для задачи остался active-step lock, указывающий на шаг, который сейчас
  НЕ в статусе `running` (например `skipped`), и выполняется
  `owl step reset TASK STEP`
- THEN active-step lock задачи снимается
- AND команда завершается успехом (без ошибки `step_not_running` как
  непреодолимого тупика)
- AND оператору не нужно прибегать к `owl step start --force`

#### Scenario: reset running-шага сохраняет прежнее поведение
- WHEN шаг находится в `status: running` и выполняется `owl step reset TASK STEP`
- THEN шаг возвращается в `pending` (`Statuses::DEFAULT`)
- AND active-step lock этого шага снимается

### Requirement: отсутствие lock'а не ломает команды

The system SHALL treat the absence of an active-step lock as a successful no-op
for `skip`, `abandon`, and `reset`.

#### Scenario: skip/reset без существующего lock'а
- WHEN для задачи нет active-step lock, и выполняется `owl step skip` или
  `owl step reset`
- THEN команда выполняется штатно без ошибки про отсутствующий lock

# Edge cases

- **Match-семантика.** Снятие lock'а в `skip` ДОЛЖНО проверять, что lock
  относится именно к снимаемому шагу (как `step_reset.rb#clear_active_step_lock`
  через `active_step_lock_matches?`), чтобы не сорвать lock параллельно
  запущенного другого шага той же задачи. (Поскольку lock per-task и running-шаг
  допускается один, коллизия маловероятна, но контракт сохраняем.)
- **reset non-running без lock'а.** Если шаг не `running` И lock'а нет, нужно
  решить на стадии design/plan: возвращать прежний `step_not_running` или
  трактовать как успешный no-op. Recovery-снятие должно срабатывать именно
  когда есть что снимать (stale-lock present).
- **Concurrency.** Изменения касаются per-task active-step lock; поведение
  при нескольких сессиях должно остаться корректным — снятие lock'а не должно
  затрагивать claim/heartbeat-лизы (отдельный механизм).
- **Backward compatibility.** Не менять форму JSON-ответов существующих команд
  несовместимо; добавление снятия lock'а — поведенческое расширение (patch/minor
  по SemVer, без слома on-disk формата). `step_not_running` как код ошибки
  может перестать возвращаться для случая «есть stale-lock» — оценить, не
  контракт ли это для потребителей.
- **Layering / FS-доступ.** Вся работа с lock-файлом идёт через
  `Steps::Api.active_step_lock_*` фасады и `Internal::ActiveStepLock`, без сырых
  FS-чтений из CLI (см. `docs/agents/27_Owl_Ruby_code_architecture.md`).
- **Error handling / идемпотентность.** Повторный `skip`/`reset` после успешного
  снятия lock'а — безопасный no-op.

# Acceptance criteria

- `owl step skip` для running-шага, владеющего active-step lock'ом, снимает этот
  lock (по match'у); чужой lock не трогается.
- `owl task abandon` для задачи с running-шагом снимает active-step lock задачи.
- `owl step reset` снимает stale active-step lock, относящийся к целевому шагу,
  даже когда шаг не в статусе `running`; `step start --force` для этого больше
  не требуется.
- Прежнее поведение `reset` для running-шага (возврат в `pending` + снятие
  lock'а) сохранено.
- Отсутствие lock'а трактуется как успешный no-op во всех трёх командах.
- Изменения проходят через `Steps::Api` / `Internal::ActiveStepLock` без сырых
  FS-доступов в CLI-слое; покрыты RSpec (включая 100% line coverage для
  затронутых `lib/owl/**/api.rb`).
- `Owl::VERSION` поднят и добавлена запись в `CHANGELOG.md` в том же коммите
  (поведенческое изменение CLI; SemVer-уровень определяется на стадии design/plan).
