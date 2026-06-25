---
status: approved
summary: "Запись task.yaml — read-modify-write без сериализации между сессиями: AtomicYamlWriter спасает от битого файла, но не от lost-update, когда трекер-операция (set-status/label/dep) и step-мутация (или две трекер-операции) из разных сессий пишут одну task.yaml. Ввести per-task mutation lock вокруг каждого read-modify-write, как IndexWriter для index.yaml."
---

# Problem

Каждая мутация `tasks/<ID>/task.yaml` — это **read-modify-write**: `TaskReader.read`
→ изменить payload → `AtomicYamlWriter.write` (+ иногда `IndexWriter.rebuild`).
`AtomicYamlWriter` гарантирует атомарную замену файла (rename) — файл не побьётся.
Но read и write **не сериализованы между собой**: при конкуренции двух писателей

- A: read(payload) … B: read(payload) … A: write(status) … B: write(label)

запись B построена на устаревшем payload и **затирает изменение A** (lost update).

Сериализации записи task.yaml сегодня нет. Claim-lease сериализует *работу над
задачей* (один владелец активной работы), но **трекер-операции lease не берут**:
`owl task set-status / label / dep add|rm / set-priority / abandon` мутируют
task.yaml из любой сессии без lease. Поэтому реальны незащищённые сценарии:

1. Две трекер-операции одной задачи из разных сессий (`set-status` ∥ `label add`).
2. Трекер-операция из сессии B параллельно со step-мутацией (`step complete`)
   из сессии A — обе пишут одну task.yaml.
3. `owl task delete` скраббит `blocked_by` *зависимых* задач
   (`Deleter#scrub_task_blocked_by`) — мутирует **чужие** task.yaml, которые в этот
   момент может менять другая сессия.

Прецедент решения уже есть: `IndexWriter` (TASK-0021) сериализует все перезаписи
`index.yaml` под именованным `Owl::Locks`-локом с блокирующим acquire (retry+deadline
поверх non-blocking FileLock). Нужен аналог для каждого read-modify-write task.yaml.

# Goal

Ввести **per-task mutation lock**: каждый read-modify-write одной `task.yaml`
выполняется под локом, скоупленным по `task_id` (`Owl::Locks` имя `task-<id>`), так
что конкурентные мутации одной задачи сериализуются (read и write — под одним локом,
lost-update исключён), а мутации *разных* задач идут параллельно. Лок применяется ко
ВСЕМ read-modify-write путям task.yaml в обоих namespace (`tasks/internal` и
`steps/internal`). Без deadlock и без изменения наблюдаемого однопоточного поведения.

# Scenarios

### Requirement: конкурентные мутации одной задачи не теряются

The system SHALL serialize concurrent read-modify-write mutations of a single
`task.yaml` so that no update is lost.

#### Scenario: трекер-операция и step-мутация не затирают друг друга
- WHEN из двух сессий одновременно идут `owl task label add` и `owl step complete`
  одной задачи
- THEN после обеих операций task.yaml содержит И новый label, И новый статус шага
  (ни одно изменение не потеряно)

#### Scenario: две трекер-операции одной задачи сериализуются
- WHEN из двух сессий одновременно идут `set-status` и `dep add` одной задачи
- THEN финальный task.yaml отражает оба изменения

### Requirement: мутации разных задач параллельны

The system SHALL scope the lock per task so mutations of distinct tasks do not
block each other.

#### Scenario: лок скоуплен по task_id
- WHEN одновременно мутируются task.yaml двух РАЗНЫХ задач
- THEN они не сериализуются друг с другом (лок `task-<id>` различается)

### Requirement: блокирующий acquire с таймаутом

The system SHALL acquire the per-task lock with a bounded blocking retry
(mirroring IndexWriter), surfacing `lock_held` only past the deadline.

#### Scenario: ожидание освобождения и таймаут
- WHEN лок задачи удерживается другим писателем
- THEN acquire ретраит с backoff до дедлайна; при освобождении — берёт лок и
  продолжает; если лок жив за дедлайном — возвращает `lock_held`

# Edge cases

- **Read под локом.** Лок ОБЯЗАН охватывать read+modify+write вместе (read внутри
  лока), иначе lost-update сохраняется. Оборачивать на уровне internal-writer (точки
  read-modify-write), НЕ на уровне Api (там высокоуровневые шаги типа verify-gate).
- **Реентерация запрещена.** FileLock не реентерабельный: один мутатор НЕ должен,
  держа task-lock задачи, вызывать другой мутатор той же задачи (иначе self-deadlock
  до `lock_held`). Проверить отсутствие вложенных task-lock одной задачи.
- **Порядок локов (deadlock).** Внутри мутаторов берётся index-lock
  (`IndexWriter.rebuild`). Порядок всегда `task-lock → index-lock`; никто не берёт
  task-lock, держа index-lock. Сохранить этот единый порядок. `Deleter`: скрабить
  зависимые задачи под их task-lock ОТДЕЛЬНО от index-rebuild (не вложенно).
- **Cross-task (delete scrub, dependency add).** Писать чужую task.yaml только под её
  task-lock; не удерживать несколько task-lock одновременно (брать/освобождать по
  одной задаче), чтобы не словить lock-ordering deadlock.
- **steps StatusWriter.update.** Принимает `tasks_root:`, не `root:`; для лока нужен
  `root` — пробросить `root` (все 6 call-sites в `steps/api.rb` его имеют).
- **Создание/архив/перемещение — вне scope read-modify-write существующего файла.**
  `create` пишет новый файл (нет конкурента); `archive/mover` — атомарный move с
  rollback (своя дисциплина). Их не оборачивать (или отдельно обосновать).
- **TTL.** Лок — TTL'd файл; выбрать TTL с запасом на самый долгий read-modify-write
  (не verify-gate, т.к. оборачиваем только writer). Релиз — в `ensure`.
- **Версионирование.** Поведенческое усиление конкурентности (новый лок) → minor bump
  VERSION + CHANGELOG.

# Acceptance criteria

- [ ] Новый per-task mutation lock (`Owl::Locks` имя `task-<id>`) с блокирующим
  acquire (retry+deadline, как IndexWriter), релиз в `ensure`.
- [ ] Каждый read-modify-write существующей task.yaml выполняется под этим локом:
  `StatusWriter` (set-status), `LabelWriter`, `DependencyWriter` (add/rm),
  `AbandonWriter`, `PlanApproval` (approve/clear), `set_step_variant`,
  `Deleter#scrub_task_blocked_by` (per задача), `steps/internal/StatusWriter.update`
  (start/complete/reset/skip/reopen).
- [ ] Лок скоуплен по `task_id`; мутации разных задач параллельны.
- [ ] Порядок `task-lock → index-lock` сохранён; нет вложенных task-lock одной
  задачи (нет self-deadlock); cross-task scrub берёт по одному локу.
- [ ] Concurrency-тесты (по образцу `index_writer_spec`): сериализация/таймаут/
  retry-release; lost-update не происходит; разные задачи не блокируются.
- [ ] Однопоточное поведение не изменилось; rspec зелёный; 100% покрытие тронутых
  `**/api.rb`; RuboCop net-zero; minor bump VERSION + CHANGELOG.
