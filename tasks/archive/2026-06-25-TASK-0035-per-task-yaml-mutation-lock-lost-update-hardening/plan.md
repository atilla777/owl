---
status: approved
summary: "Новый TaskMutationLock (acquire по образцу IndexWriter, имя task-<id>); обернуть 8 internal read-modify-write мутаторов task.yaml в обоих namespace; steps StatusWriter.update получает root. Concurrency + ensure-release + lost-update тесты. minor bump 0.17.2→0.18.0."
---

# Goal

Сериализовать каждый read-modify-write `task.yaml` под per-task локом `task-<id>`,
исключив lost-update между трекер-операциями и step-мутациями из разных сессий, без
deadlock и без изменения однопоточного поведения.

# Scope

- NEW `lib/owl/tasks/internal/task_mutation_lock.rb` — `with_lock(root:, task_id:,
  locks:, clock:, sleeper:)`.
- Обернуть: `tasks/internal/{status_writer,label_writer,dependency_writer,
  abandon_writer,plan_approval,deleter}.rb`, `tasks/backends/filesystem.rb`
  (`set_step_variant`), `steps/internal/status_writer.rb` (`update` + `root:`).
- `lib/owl/version.rb` + `CHANGELOG.md` — minor bump 0.17.2 → 0.18.0.

# Constraints

- Лок ОБЯЗАН охватывать read+modify+write (read под локом). Оборачивать на уровне
  internal-writer, НЕ Api.
- Имя лока `task-<id>` (per-task; разные задачи параллельны).
- Порядок `task-lock → index-lock`; нет вложенных task-lock одной задачи (нет
  self-deadlock); cross-task scrub берёт по одному локу, до index-rebuild.
- Релиз в `ensure` (даже при исключении).
- НЕ оборачивать create/archive-move/current_pointer/index_rebuilder.
- Публичные сигнатуры `Tasks::Api`/`Steps::Api` без изменений; CLI/JSON без изменений.
- 100% покрытие тронутых `**/api.rb`; RRuboCop net-zero; rspec зелёный.
- Constitution §7.1: minor bump VERSION + CHANGELOG.

# Files to inspect

- `lib/owl/tasks/internal/index_writer.rb` — образец blocking-acquire (скопировать
  паттерн: ACQUIRE_TIMEOUT_SECONDS, RETRY_SLEEP_SECONDS, acquire-loop, ensure-release).
- `lib/owl/locks/api.rb` — `acquire(root:, name:, ttl:, token:, steal:)` /
  `release(root:, name:, token:)`.
- Все 8 мутаторов (см. Scope) — точки read-modify-write.
- `lib/owl/steps/api.rb` — 6 call-sites `Internal::StatusWriter.update` (пробросить root).
- `lib/owl/tasks/internal/deleter.rb` — `clean_dangling_refs`/`scrub_task_blocked_by`.
- `spec/owl/tasks/internal/index_writer_spec.rb` — образец concurrency-теста
  (clock double, sleeper-driven release, lock_held timeout, leaf release-on-raise).

# Checklist

- [ ] `task_mutation_lock.rb`: `with_lock(root:, task_id:, locks: Owl::Locks::Api,
      clock: Time, sleeper: ->(s){sleep(s)})` + приватный `acquire` (retry на
      `:lock_held` до deadline) + `lock_name(task_id)` = `"task-#{task_id}"`; релиз в
      ensure; вернуть err лока или результат блока.
- [ ] Обернуть `StatusWriter.call` (tasks) — весь read→write→IndexWriter под task-lock.
- [ ] Обернуть `LabelWriter.mutate` (покрывает add/remove).
- [ ] Обернуть `DependencyWriter.add` и `.remove` (лок на `task_id`).
- [ ] Обернуть `AbandonWriter.call`.
- [ ] Обернуть `PlanApproval.approve` и `.clear`.
- [ ] Обернуть `filesystem#set_step_variant` (read→write под `@root`/task-lock).
- [ ] `Deleter#scrub_task_blocked_by`: обернуть read-modify-write каждой затронутой
      задачи в task-lock ЭТОЙ задачи (по одному; `clean_dangling_refs` остаётся до
      `IndexWriter.rebuild`). Нужен `root` в scrub — пробросить.
- [ ] `steps/internal/StatusWriter.update(tasks_root:, task_id:, step_id:,
      attributes:, root:)`: обернуть read→write в `TaskMutationLock.with_lock(root:,
      task_id:)`; пробросить `root` из 6 call-sites в `steps/api.rb`.
- [ ] Проверить отсутствие реентерации: ни один обёрнутый writer не вызывает другой
      writer той же задачи, держа лок (особое внимание steps `complete` →
      `ArchiveFinalizer` — оно после `update`, лок уже отпущен).
- [ ] `CHANGELOG.md` (Changed): per-task mutation lock — все read-modify-write
      task.yaml сериализованы под `task-<id>`, lost-update между трекер- и
      step-мутациями исключён; мутации разных задач параллельны.
- [ ] `lib/owl/version.rb`: 0.17.2 → 0.18.0.

# Tests and verification

- [ ] TaskMutationLock unit (по образцу index_writer_spec): acquire/serialize/timeout
      (`lock_held` за дедлайном), retry-release через sleeper, release в ensure при
      исключении в блоке, имя лока `task-<id>` (разные id не конфликтуют).
- [ ] Lost-update: смоделировать конкуренцию — мутация B под удержанным локом A ждёт/
      ретраит; после релиза A видит свежий payload (например через sleeper, который
      выполняет вторую мутацию). Утверждать, что оба изменения присутствуют.
- [ ] Регрессия: однопоточные пути (set-status/label/dep/abandon/plan/variant/step
      complete) ведут себя как раньше; существующие тесты зелёные.
- [ ] `bundle exec rspec` зелёный, 0 failures; 100% покрытие `**/api.rb`.
- [ ] `bundle exec rubocop <тронутые файлы>` net-zero.

# Smoke test

```
# базовая работоспособность (однопоточно): мутаторы работают как прежде
owl task set-status TASK-X on_hold && owl task label TASK-X add foo
owl task dep add TASK-Y --on TASK-X && owl task ready
owl step start TASK-Z <step> && owl step reset TASK-Z <step>
# лок-файлы task-<id> появляются/исчезают под local_state во время мутации
```

# Out of scope

- Архивный move / создание новой задачи (отдельная дисциплина / нет конкурента).
- DRY-вынесение общего blocking-acquire из IndexWriter (cleanup-кандидат, опц.).
- false-conditional task-level auto-select; P3; F2.2.
