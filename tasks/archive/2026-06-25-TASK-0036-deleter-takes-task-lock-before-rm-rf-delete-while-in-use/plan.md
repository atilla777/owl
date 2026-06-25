---
status: approved
summary: "Deleter.call: обернуть rm_rf в TaskMutationLock.with_lock(root:, task_id:) (блок возвращает Result.ok); clean_dangling_refs + IndexWriter.rebuild остаются после/вне лока. Concurrency-тест + регрессия. minor bump 0.18.0→0.19.0."
---

# Goal

`Deleter.call` берёт `task-<id>` лок удаляемой задачи на время `rm_rf`, без
вложенности с child-локами `clean_dangling_refs` (нет deadlock).

# Scope

- `lib/owl/tasks/internal/deleter.rb` — обернуть `rm_rf` в `TaskMutationLock.with_lock`.
- `lib/owl/version.rb` + `CHANGELOG.md` — minor bump 0.18.0 → 0.19.0.

# Constraints

- Под локом удаляемой задачи — ТОЛЬКО `rm_rf`. `clean_dangling_refs` и
  `IndexWriter.rebuild` — после, вне этого лока.
- `task_not_found` guard — до лока.
- `lock_held` (acquire-фейл за дедлайном) пробрасывается как recoverable err delete.
- Существующее поведение delete (dangling cleanup, index rebuild, claim reset) не
  меняется.
- 100% покрытие тронутых `**/api.rb`; RuboCop net-zero; rspec зелёный.
- Constitution §7.1: bump VERSION + CHANGELOG в том же коммите.

# Files to inspect

- `lib/owl/tasks/internal/deleter.rb` (`call`, `clean_dangling_refs`).
- `lib/owl/tasks/internal/task_mutation_lock.rb` (with_lock сигнатура/возврат).
- `spec/owl/tasks/internal/task_mutation_lock_spec.rb` (образец concurrency-теста:
  foreign holder + clock/sleeper).
- спек(и) Deleter / `owl task delete` — куда добавить регрессию/concurrency.

# Checklist

- [ ] В `Deleter.call`: после `task_not_found` guard обернуть `FileUtils.rm_rf(
      task_dir.to_s)` в `TaskMutationLock.with_lock(root: root, task_id: task_id.to_s)`;
      блок возвращает `Result.ok` (для корректного `.err?`); `return <lock_result> if
      <lock_result>.err?`.
- [ ] `clean_dangling_refs(...)` и `IndexWriter.rebuild(...)` — ПОСЛЕ блока, вне лока.
- [ ] require на `task_mutation_lock` в deleter.rb (если ещё нет).
- [ ] `CHANGELOG.md` (Changed): `owl task delete` теперь берёт `task-<id>` лок
      удаляемой задачи на время `rm_rf` (устранён delete-while-in-use хазард); cleanup
      зависимых остаётся вне этого лока (нет lock-ordering deadlock).
- [ ] `lib/owl/version.rb`: 0.18.0 → 0.19.0.

# Tests and verification

- [ ] Concurrency (по образцу task_mutation_lock_spec): пока `task-X` лок удерживается
      «чужим» держателем, `Deleter.call(X)` ретраит; после релиза (в sleeper) —
      удаляет. ИЛИ: lock_held за дедлайном → delete возвращает recoverable err и НЕ
      удаляет каталог.
- [ ] Регрессия: обычный delete (без контенции) удаляет каталог, чистит dangling
      `blocked_by` зависимых, ребилдит индекс, сбрасывает claim — как раньше.
- [ ] `bundle exec rspec` зелёный, 0 failures; покрытие `**/api.rb` без регрессий.
- [ ] `bundle exec rubocop lib/owl/tasks/internal/deleter.rb` net-zero.

# Smoke test

```
# обычный delete работает; lock-файл task-<id> не висит после
owl task create --workflow quick --title gone   # TASK-N
owl task delete TASK-N --force && owl task index rebuild
ls .owl/local/locks/ | grep task-TASK-N || echo "no lingering lock"
```

# Out of scope

- conditional-aware availability (отдельная задача).
- Изменение clean_dangling_refs/scrub (уже под child-локами из TASK-0035).
- P3 / F2.2.
