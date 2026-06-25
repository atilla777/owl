---
status: passed
summary: "Objective verification of TASK-0036 (deleted-task mutation lock around `owl task delete`'s rm_rf). `bundle exec rspec` → 1980 examples, 0 failures, 1 pending (pre-existing storage backend-contract concurrent-writes spec), exit 0; the SimpleCov public-API 100%-line at_exit gate did NOT trip ⇒ **/api.rb coverage holds. README stayed clean (`git status --short README.md docs/README.md` empty) — no `git checkout README.md` needed. `bundle exec rubocop lib/owl/tasks/internal/deleter.rb spec/owl/tasks/api_delete_spec.rb` → 2 files inspected, no offenses, exit 0. Grep confirmed the block under `with_lock(deleted)` holds ONLY `FileUtils.rm_rf` + `Result.ok(:removed)`, and that `clean_dangling_refs` / `IndexWriter.rebuild` are AFTER `remove_dir_locked` returns (outside the lock). I ran an INDEPENDENT throwaway-project smoke (Dir.mktmpdir, auto-removed, NOT the implementer's spec): (a) a normal `Tasks::Api.delete` removed the task dir; (b) a foreign-token holder on `task-<id>` + a clock-double past `ACQUIRE_TIMEOUT_SECONDS` ⇒ `Internal::Deleter.call` returned err code `:lock_held` with `tasks/<id>` STILL PRESENT and the lock file at `<root>/.owl/local/task-<id>.lock` (outside the doomed dir). No git mutations, no `bin/owl step` commands; working tree left clean. No failures or blockers."
---

# Summary

Objective verification of TASK-0036 — taking the deleted task's own `task-<id>`
mutation lock around `FileUtils.rm_rf` in `Internal::Deleter`. The decisive
checks pass: the full suite is green and exits 0 (the public-API coverage gate
did not trip), RuboCop is clean on the delta, the `with_lock(deleted)` block
provably contains only the `rm_rf`, and an independent two-scenario smoke proved
both that an uncontended delete still removes the dir and that a contended delete
surfaces `:lock_held` while leaving the directory intact. README was not dirtied.
Outcome: **passed**.

# Commands

```
git status --short README.md docs/README.md                                  # → clean (no checkout needed)
bundle exec rspec                                                            # full suite
bundle exec rubocop lib/owl/tasks/internal/deleter.rb spec/owl/tasks/api_delete_spec.rb

# Code-shape confirmation (only rm_rf under the lock; cleanup/rebuild outside):
#   read lib/owl/tasks/internal/deleter.rb lines 22-73 — remove_dir_locked body
#   is FileUtils.rm_rf + Result.ok(:removed); clean_dangling_refs (line 40) and
#   IndexWriter.rebuild (line 42) are AFTER `return removed if removed.err?` (l.38).

# Independent smoke (throwaway Dir.mktmpdir --root project, auto-removed):
#   1) Tasks::Api.delete(real task)        → dir removed
#   2) Locks::Api.acquire(task-<id>,foreign) + clock-double past deadline,
#      Internal::Deleter.call(..., clock:, sleeper: no-op)
#                                          → err :lock_held, dir still present
ruby scratchpad/smoke2.rb
```

# Outcomes

- **`git status --short README.md docs/README.md`** → no output. README/docs
  README were NOT dirtied; **no `git checkout README.md` was needed** this run.
- **`bundle exec rspec`** → `1980 examples, 0 failures, 1 pending`, exit **0**.
  The single pending is the pre-existing storage backend-contract
  concurrent-writes spec (unrelated). The SimpleCov public-API 100%-line `at_exit`
  gate did NOT trip (process exited 0), so `lib/owl/**/api.rb` coverage holds —
  consistent with the public `Tasks::Api.delete` signature being unchanged.
- **`bundle exec rubocop lib/owl/tasks/internal/deleter.rb
  spec/owl/tasks/api_delete_spec.rb`** → `2 files inspected, no offenses
  detected`, exit **0**. (Only the two pre-plugin-migration warnings about
  `require:` vs `plugins:` in `.rubocop.yml` — repo-wide, pre-existing, not from
  this change.)
- **Code-shape (only-rm_rf-under-lock)** → `remove_dir_locked` (deleter.rb:66-73)
  wraps exactly `FileUtils.rm_rf(task_dir.to_s)` + `Result.ok(:removed)` in
  `TaskMutationLock.with_lock(deleted)`; `clean_dangling_refs` (l.40) and
  `IndexWriter.rebuild` (l.42) run only after `remove_dir_locked` returns and the
  `return removed if removed.err?` guard (l.38) — both OUTSIDE the lock. No
  `lock(deleted) -> lock(child)` nesting exists.
- **Independent smoke — scenario 1 (uncontended delete)** → `Tasks::Api.delete`
  returned ok, `tasks/<id>` removed (`dir_gone?=true`).
- **Independent smoke — scenario 2 (contended delete)** → with a foreign token
  holding `task-<id>` and a clock-double returning `now` then
  `now + ACQUIRE_TIMEOUT_SECONDS + 1`, `Internal::Deleter.call` returned err code
  `:lock_held` and `tasks/<id>` was **still present** (`dir_present?=true`). The
  lock file resolved to `<root>/.owl/local/task-<id>.lock` — OUTSIDE the task dir,
  so it would survive an rm_rf and release in `with_lock`'s `ensure`. (First smoke
  attempt mis-asserted because deleted task ids are REUSED — the second
  `task create` got `TASK-0001` again, not `TASK-0002`; re-run reading the real
  returned id reproduced the expected result.)

# Not run

- `bin/owl step ...` and any git mutation — out of scope for this review (and
  explicitly prohibited).
- A true multi-process concurrent delete-vs-delete race — the lock-ordering
  argument was verified by static code inspection (at most one task lock held at
  a time) plus the injected-clock `lock_held` test, not by a live race harness.

# Failures or blockers

None.

# Residual risks

- Benign TOCTOU between the pre-lock `task_not_found` check and lock acquisition
  (a parallel delete of the same task can make the later caller `rm_rf` an
  already-gone path and still report `removed: true`) — harmless, no deadlock.
- Verification of the deadlock-avoidance property is by inspection + the
  single-task `lock_held` unit test, not a live two-delete race; acceptable given
  the code holds at most one task lock at any instant.
