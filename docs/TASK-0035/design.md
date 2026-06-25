---
status: shipped
summary: "Новый Owl::Tasks::Internal::TaskMutationLock.with_lock(root:, task_id:){block} — блокирующий acquire (retry+deadline) под Owl::Locks имя task-<id>, релиз в ensure. Обернуть КАЖДЫЙ internal read-modify-write task.yaml (tasks/internal + steps/internal/StatusWriter.update, которому пробросить root). Порядок task→index; без реентерации; cross-task scrub по одному локу."
---

# Context

Мутаторы task.yaml делают read-modify-write без сериализации read↔write
(см. brief). Прецедент — `IndexWriter` (блокирующий acquire поверх non-blocking
`Owl::Locks` FileLock: retry с backoff до deadline, релиз в ensure). `Owl::Locks::Api.acquire(root:, name:)` принимает произвольное имя и пишет TTL-файл под
local_state. Все step-мутаторы зовут `steps/internal/StatusWriter.update` из
`steps/api.rb`, где `root` доступен.

# Decision

## 1. Новый хелпер `Owl::Tasks::Internal::TaskMutationLock`
```
LOCK_PREFIX = 'task-'
ACQUIRE_TIMEOUT_SECONDS = 10.0
RETRY_SLEEP_SECONDS = 0.02

def with_lock(root:, task_id:, locks: Owl::Locks::Api, clock: Time,
              sleeper: ->(s){ sleep(s) })
  lock = acquire(root:, task_id:, locks:, clock:, sleeper:)   # name "task-<id>"
  return lock if lock.err?
  token = lock.value[:token]
  begin
    yield                      # read-modify-write блока выполняется ПОД локом
  ensure
    locks.release(root:, name: lock_name(task_id), token:)
  end
end
```
`acquire` — копия паттерна `IndexWriter.acquire` (retry на `:lock_held` до deadline).
Имя лока `"task-#{task_id}"` → разные задачи параллельны. `with_lock` возвращает либо
err лока (`lock_held`/backend err), либо результат блока. (Если хочется DRY — вынести
общий blocking-acquire в шаренный хелпер и переиспользовать в IndexWriter; НЕ
обязательно, чтобы не трогать рабочий IndexWriter — допустима параллельная копия
паттерна. Зафиксировать как cleanup-кандидат.)

## 2. Уровень оборачивания — internal writer (точка read-modify-write)
Оборачиваем КАЖДЫЙ self-contained read-modify-write блок (read+modify+write вместе),
НЕ высокоуровневый Api. Это:
- даёт read под локом (иначе lost-update остаётся);
- избегает реентерации (внутри одного writer нет вложенного мутатора той же задачи);
- не держит лок во время verify-gate/validation (они выше writer'а).

Обернуть:
| Файл | Точка |
|---|---|
| `tasks/internal/status_writer.rb` | `call` (read→write status + IndexWriter) |
| `tasks/internal/label_writer.rb` | `mutate` (add/remove) |
| `tasks/internal/dependency_writer.rb` | `add`, `remove` (пишут task_id) |
| `tasks/internal/abandon_writer.rb` | `call` |
| `tasks/internal/plan_approval.rb` | `approve`, `clear` |
| `tasks/backends/filesystem.rb` | `set_step_variant` |
| `tasks/internal/deleter.rb` | `scrub_task_blocked_by` (per affected задача) |
| `steps/internal/status_writer.rb` | `update` (+ новый `root:` param) |

`steps/internal/StatusWriter.update`: добавить `root:` (в дополнение к `tasks_root:`),
обернуть тело в `TaskMutationLock.with_lock(root:, task_id:)`. 6 call-sites в
`steps/api.rb` (start/complete/reset/skip/reopen + idempotent) передают `root` (есть).

## 3. Дисциплина локов (deadlock-free)
- **Единый порядок `task-lock → index-lock`.** Мутаторы, зовущие `IndexWriter.rebuild`,
  делают это ВНУТРИ своего task-lock (index-lock — самый внутренний, leaf). Никто не
  берёт task-lock, держа index-lock.
- **Без реентерации.** Ни один блок под task-lock задачи X не вызывает другой мутатор
  X, берущий task-lock X. (Проверить `steps complete` → `ArchiveFinalizer`: вызывается
  ПОСЛЕ `update` (лок уже отпущен), последовательно — ок.)
- **Cross-task — по одному локу.** `Deleter#scrub_task_blocked_by` берёт task-lock
  КАЖДОЙ затронутой зависимой задачи по очереди (acquire→write→release), не удерживая
  несколько одновременно. `clean_dangling_refs` идёт ДО `IndexWriter.rebuild`, так что
  никакой task-lock не удерживается во время index-lock. `DependencyWriter` пишет
  только `task_id` (depends_on только читается) → лок лишь на `task_id`.

## 4. Что НЕ оборачиваем
- `TaskWriter.write`/`filesystem#create` — создание нового файла (нет конкурента на
  существующий). (Если внутри set_step_variant используется TaskWriter.write — лок
  берётся вокруг read+write в set_step_variant, не в TaskWriter.)
- `archive/mover` — атомарный move с rollback (своя дисциплина; перемещение, не
  read-modify-write). Вне scope.
- `current_pointer`/`index_rebuilder` — не task.yaml.

# Alternatives

- **Оборачивать на уровне Api (tasks/api.rb, steps/api.rb).** Охватило бы вложенные
  мутаторы → реентерация/self-deadlock (FileLock не реентерабельный) и держало бы лок
  во время verify-gate. Отклонено в пользу обёртки на уровне writer.
- **Только AtomicYamlWriter под локом (read вне лока).** Не решает lost-update (read
  устаревает). Отклонено.
- **Глобальный (не per-task) лок записи task.yaml.** Сериализует мутации РАЗНЫХ задач
  без нужды. Отклонено — лок скоуплен по task_id.
- **Полагаться на claim-lease.** Трекер-операции lease не берут (см. brief). Лок нужен
  независимо от lease.

# Risks

- **Реентерация/self-deadlock.** Митигировано обёрткой на уровне writer + проверкой
  отсутствия вложенных мутаторов одной задачи. Тест на «мутатор не зовёт себя под
  локом».
- **Удержание лока (TTL).** Writer-блок короткий (read+write+index-rebuild); TTL с
  запасом. Релиз в ensure даже при исключении (тест на это, как leaf-тест IndexWriter).
- **Покрытие api.rb.** `tasks/api.rb`/`steps/api.rb` уже покрыты; новый internal лок —
  покрыть concurrency-тестами. `filesystem#set_step_variant` (backend) — не api.rb.
- **Регрессия однопоточного пути.** Без контенции лок берётся/освобождается мгновенно;
  поведение и существующие тесты неизменны. Полный rspec — контроль.

# API

- **CLI/JSON:** без изменений (внутреннее усиление конкурентности).
- **Ruby (internal):**
  - NEW `Owl::Tasks::Internal::TaskMutationLock.with_lock(root:, task_id:, locks:,
    clock:, sleeper:)`.
  - `steps/internal/StatusWriter.update` получает `root:`-параметр.
  - Перечисленные мутаторы оборачивают свой read-modify-write в `with_lock`.
  - Публичные сигнатуры `Tasks::Api`/`Steps::Api` не меняются.
