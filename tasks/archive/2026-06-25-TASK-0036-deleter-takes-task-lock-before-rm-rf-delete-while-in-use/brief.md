---
status: approved
summary: "Deleter.call делает FileUtils.rm_rf удаляемой задачи БЕЗ её per-task mutation lock — delete-while-in-use хазард: конкурентный мутатор той же задачи может писать task.yaml, который удаляется из-под него. Обернуть rm_rf (только его) в TaskMutationLock самой задачи; clean_dangling_refs (child-locks) оставить ВНЕ этого лока, чтобы избежать lock-ordering deadlock."
---

# Problem

TASK-0035 ввёл per-task mutation lock на все read-modify-write `task.yaml`. Но
`Deleter.call` (`owl task delete`) удаляет каталог задачи `FileUtils.rm_rf(task_dir)`
**без** взятия mutation-lock самой удаляемой задачи (находка ревью TASK-0035).
Это delete-while-in-use хазард: другая сессия может в этот момент мутировать
`task.yaml` той же задачи (через какой-нибудь writer под `task-<id>` локом), а delete
снесёт каталог из-под неё — частичная запись/гонка.

# Goal

Взять per-task mutation lock удаляемой задачи (`task-<id>`) на время `rm_rf`, так что
delete и любой конкурентный мутатор той же задачи взаимно исключаются. **Только**
`rm_rf` под локом удаляемой задачи; `clean_dangling_refs` (который берёт task-lock
КАЖДОЙ зависимой задачи по одной) обязан остаться ВНЕ этого лока — иначе вложенность
`lock(deleted) → lock(child)` создаёт classic lock-ordering deadlock между двумя
параллельными delete (A удаляет X и скраббит Y; B удаляет Y и скраббит X).

# Scenarios

### Requirement: delete берёт лок удаляемой задачи на rm_rf

The system SHALL hold the deleted task's per-task mutation lock while removing
its directory.

#### Scenario: delete и конкурентный мутатор той же задачи сериализуются
- WHEN `owl task delete X` выполняется, пока другая сессия держит `task-X` лок
  (мутирует X)
- THEN delete ждёт освобождения лока (retry до дедлайна), затем удаляет; они не
  пересекаются (нет частичной записи в удаляемый файл)

### Requirement: lock-ordering без deadlock

The system SHALL NOT hold the deleted task's lock while acquiring other tasks'
locks during dangling-ref cleanup.

#### Scenario: clean_dangling_refs вне лока удаляемой задачи
- WHEN delete X скраббит `blocked_by` зависимых задач (берёт их `task-<id>` локи)
- THEN это происходит ПОСЛЕ освобождения лока X (не вложенно), так что два
  параллельных delete не могут зайти в lock-ordering deadlock

# Edge cases

- **Только rm_rf под локом.** Обернуть в `TaskMutationLock.with_lock(root:,
  task_id:)` ровно `FileUtils.rm_rf(task_dir)`. `clean_dangling_refs` и
  `IndexWriter.rebuild` — после, вне лока удаляемой задачи (порядок сохраняется:
  никакой task-lock не удерживается во время index-lock).
- **task_not_found ДО лока.** Проверка существования каталога остаётся до взятия
  лока (не лочить несуществующую задачу).
- **Лок-файл переживает rm_rf.** Лок живёт под `local_state` (не в `task_dir`), так
  что `rm_rf task_dir` его не трогает; release в `ensure` удалит лок-файл.
- **lock_held за дедлайном.** Если лок удаляемой задачи занят дольше дедлайна —
  `with_lock` вернёт recoverable `lock_held`; delete вернёт эту ошибку (тот же
  fail-safe, что у прочих мутаторов; лучше, чем снести из-под живого писателя).
- **Версионирование.** Усиление конкурентности delete → minor bump VERSION +
  CHANGELOG (или patch как concurrency-fix; выбрать по SemVer — новое наблюдаемое
  поведение блокировки → minor).

# Acceptance criteria

- [ ] `Deleter.call` оборачивает `FileUtils.rm_rf(task_dir)` в
  `TaskMutationLock.with_lock(root:, task_id:)` (лок удаляемой задачи).
- [ ] `clean_dangling_refs` и `IndexWriter.rebuild` выполняются ВНЕ лока удаляемой
  задачи (нет вложенности `lock(deleted) → lock(child)`; нет lock-ordering deadlock).
- [ ] `task_not_found` по-прежнему до лока; release в `ensure`; `lock_held` за
  дедлайном пробрасывается как recoverable.
- [ ] Регрессионные тесты: delete под удержанным `task-X` локом ждёт/ретраит;
  существующее поведение delete (удаление, dangling-ref cleanup, index rebuild,
  claim reset) не изменилось.
- [ ] rspec зелёный; 100% покрытие тронутых `**/api.rb`; RuboCop net-zero; bump
  VERSION + CHANGELOG.
