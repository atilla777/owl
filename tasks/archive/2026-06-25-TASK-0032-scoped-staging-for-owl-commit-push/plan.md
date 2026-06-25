---
status: approved
summary: "GitRunner.add_scoped(exclude)+index_dirty?; Transaction.call(exclude:) с guard/retry в терминах индекса; Api.commit_push вычисляет exclude=Tasks::Api.list - текущая → tasks/<id>. Обновить fake_git тесты + новые регрессии. minor bump."
---

# Goal

Scoped-staging в `owl commit-push`: исключать каталоги других активных задач, не
ломая доставку текущей и инварианты транзакции (nothing_to_commit / idempotent
retry) при backlog.

# Scope

- `lib/owl/commit_push/internal/git_runner.rb` — `add_scoped`, `index_dirty?`.
- `lib/owl/commit_push/internal/transaction.rb` — `call(exclude:)`; guard/retry в
  терминах индекса; `flip_done`/`stage_and_guard` зовут `add_scoped`.
- `lib/owl/commit_push/api.rb` — вычисление `exclude` через `Owl::Tasks::Api.list`.
- `lib/owl/version.rb` + `CHANGELOG.md` — minor bump (0.16.1 → 0.17.0).

# Constraints

- Нет backlog (пустой exclude) → staging эквивалентен прежнему `git add -A`.
- Доступ к активным задачам только через `Owl::Tasks::Api` (без прямого FS из commit_push).
- Текущую задачу и `tasks/archive/` НЕ исключать; `tasks/index.yaml` стейджить.
- 100% покрытие `lib/owl/commit_push/api.rb` (ветки exclude: есть/нет/ошибка чтения).
- RuboCop net-zero; rspec зелёный.
- Constitution §7.1: minor bump VERSION + CHANGELOG (с known limitation) в том же коммите.

# Files to inspect

- `lib/owl/commit_push/internal/git_runner.rb` (add_all, run, Outcome).
- `lib/owl/commit_push/internal/transaction.rb` (call, stage_and_guard, flip_done,
  retry?, clean_tree?, publish).
- `lib/owl/commit_push/api.rb` (commit_push facade — точка вычисления exclude).
- `lib/owl/tasks/api.rb` (list — форма: массив хэшей с `id`).
- `spec/owl/commit_push/api_spec.rb`, `spec/owl/commit_push/locking_spec.rb`
  (fake_git: add_all/status_porcelain; ожидания add_all-twice, clean через
  status_porcelain('')).
- `spec/owl/cli/commit_push_command_spec.rb` (integration с реальным git — добавить
  backlog-сценарий, если выполнимо).

# Checklist

- [ ] `git_runner.rb`: `add_scoped(root:, exclude: [])` → пустой exclude = `git add
      -A`; иначе `git add -A -- . :(exclude)<path> …` (каждый pathspec — отдельный
      argv). `index_dirty?(root:)` → `git diff --cached --quiet` (Outcome.ok == git
      success; ok ⇒ индекс пуст). Сохранить `add_all` если на него опираются.
- [ ] `transaction.rb`: `call(..., exclude: [])`; `stage_and_guard` → `add_scoped`
      + guard по `index_dirty?.ok` (пустой индекс → nothing_to_commit); `flip_done`
      → `add_scoped`; `retry?` использует `index_dirty?.ok` вместо `clean_tree?`;
      удалить неиспользуемый `clean_tree?`. Прокинуть `exclude` во все внутренние
      вызовы.
- [ ] `api.rb`: перед `Transaction.call` собрать `exclude` =
      `Tasks::Api.list(root:)` → отфильтровать `id == task_id` → `"tasks/#{id}"`;
      на err/empty → `[]`. Передать `exclude:`.
- [ ] Обновить `fake_git` в обоих spec: добавить `add_scoped`, `index_dirty?`;
      заменить ожидания `add_all` на `add_scoped`; clean-состояние выражать через
      `index_dirty?`.
- [ ] `CHANGELOG.md` (Changed): scoped-staging — commit-push исключает каталоги
      других активных задач; guard/retry переведены на состояние индекса; known
      limitation (изменения кода чужих задач вне `tasks/` не детектируются).
- [ ] `lib/owl/version.rb`: 0.16.1 → 0.17.0.

# Tests and verification

- [ ] add_scoped: пустой exclude → `git add -A`; непустой → корректный pathspec с
      `:(exclude)` (проверить переданный argv или поведение на реальном git).
- [ ] Транзакция (fake_git): scoped-add вызывается дважды; пустой индекс
      (`index_dirty?.ok`) → nothing_to_commit; commit/push happy-path; retry-ветка по
      `index_dirty?` + unpushed.
- [ ] Api: exclude = активные минус текущая (mock Tasks::Api.list с 2+ задачами);
      одна текущая → exclude пуст; ошибка list → exclude пуст (фолбэк).
- [ ] Integration (реальный git, commit_push_command_spec): доставка с backlog
      `tasks/<O>/` (untracked) → коммит НЕ содержит `tasks/<O>/`, содержит доставку
      текущей; повтор после смоделированного push-fail идёт по retry (если
      выполнимо в текущем тест-харнессе).
- [ ] `bundle exec rspec` зелёный, 0 failures; 100% покрытие `commit_push/api.rb`.
- [ ] `bundle exec rubocop <тронутые файлы>` net-zero.

# Smoke test

```
# в этом репо: создать throwaway backlog-задачу, не доставляя её
owl task create --workflow feature --title backlog   # -> tasks/TASK-00NN (untracked)
# провести любую доставку через commit-push (или dry-проверку staging) и убедиться,
# что git diff --cached НЕ содержит tasks/TASK-00NN/, а доставка текущей — содержит
owl task delete TASK-00NN --force && owl task index rebuild   # cleanup
```

# Out of scope

- Детекция изменений кода чужих задач вне `tasks/` (known limitation).
- Изменение публичного контракта CLI commit-push (флагов).
- per-task.yaml mutation-лок; P3/F2.2.
