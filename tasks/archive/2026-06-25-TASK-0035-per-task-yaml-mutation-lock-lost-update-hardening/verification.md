---
status: passed
summary: "Objective verification of TASK-0035 (per-task tasks/<id>/task.yaml mutation lock against lost updates). bundle exec rspec → 1979 examples, 0 failures, 1 pending (pre-existing storage backend-contract concurrent-writes spec), exit 0; the SimpleCov public-API 100%-line-coverage at_exit gate did NOT trip, so **/api.rb coverage holds. README stayed clean (git status --short README.md docs/README.md empty) — no git checkout README.md needed. bundle exec rubocop on all 12 touched files → 12 files inspected, no offenses detected, exit 0. grep -n with_lock lib/owl/steps/api.rb → EMPTY (no api-level wrap ⇒ no reentrant self-deadlock). grep of all with_lock call-sites → 11 in mutators only. REAL concurrent smoke in a throwaway mktmpdir --root project: two threads each add 50 DISTINCT labels (a0..a49 / b0..b49) to the SAME task via LabelWriter.add → final payload has 100 labels, 50/50 from each thread, zero lost updates (without the lock interleaved read-modify-writes would drop entries). No git mutations, no bin/owl step commands; the smoke used Dir.mktmpdir (auto-removed) so the working tree is left clean. No failures or blockers."
---

# Summary

Objective verification of TASK-0035 — the per-task mutation lock serializing
every read-modify-write of `tasks/<id>/task.yaml`. The decisive checks pass: the
full suite is green and exits 0 (the public-API coverage gate did not trip),
RuboCop is clean on the entire delta, `lib/owl/steps/api.rb` contains no
`with_lock` (confirming there is no reentrant api-level wrap), and a real
two-thread concurrent smoke proved zero lost updates on a single task. README was
not dirtied. Outcome: **passed**.

# Commands

```
git status --short README.md docs/README.md        # → clean (no checkout needed)
grep -n "with_lock" lib/owl/steps/api.rb            # → EMPTY (no api-level wrap)
grep -rn "with_lock" lib/                           # → 11 call-sites, all in mutators
bundle exec rspec
bundle exec rubocop \
  lib/owl/tasks/internal/task_mutation_lock.rb lib/owl/steps/api.rb \
  lib/owl/steps/internal/status_writer.rb lib/owl/tasks/backends/filesystem.rb \
  lib/owl/tasks/internal/abandon_writer.rb lib/owl/tasks/internal/child_creator.rb \
  lib/owl/tasks/internal/deleter.rb lib/owl/tasks/internal/dependency_writer.rb \
  lib/owl/tasks/internal/label_writer.rb lib/owl/tasks/internal/plan_approval.rb \
  lib/owl/tasks/internal/status_writer.rb \
  spec/owl/tasks/internal/task_mutation_lock_spec.rb

# Real concurrent smoke (throwaway Dir.mktmpdir --root project, auto-removed):
#   create one task, spawn 2 threads, each LabelWriter.add 50 DISTINCT labels
#   to the SAME task, then assert all 100 survive.
ruby scratchpad/smoke.rb
```

# Outcomes

- **`git status --short README.md docs/README.md`** → no output. README was not
  dirtied; **no `git checkout README.md` was needed** this run.
- **`grep -n with_lock lib/owl/steps/api.rb`** → **EMPTY**. The step api
  (`start/complete/reopen/reset/skip/mark_running`) never wraps a `task-<id>`
  lock; each internal mutator takes/releases it in sequence, so the non-reentrant
  FileLock cannot self-deadlock.
- **`grep -rn with_lock lib/`** → 11 call-sites: step status_writer (1), task
  status_writer (1), filesystem set_step_variant + write_priority (2),
  abandon/label/dependency-add/dependency-remove/plan-approve/plan-clear/deleter
  (7), plus the `with_lock` definition. All in read-modify-write mutators.
- **`bundle exec rspec`** → `1979 examples, 0 failures, 1 pending`, exit **0**.
  - The 1 pending is the pre-existing `Storage::Backends::Filesystem`
    concurrent-writes backend-contract spec, unrelated to this task.
  - Exit 0 ⇒ the SimpleCov public-API `at_exit` gate did NOT trip; `**/api.rb`
    (incl. `steps/api.rb`, whose call-sites gained `root:`) stays at 100% line
    coverage. Overall line coverage 97.06%.
- **`bundle exec rubocop` (12 files)** → `12 files inspected, no offenses
  detected`, exit **0** (the two plugin-migration lines are pre-existing
  `.rubocop.yml` notices, not offenses). Net-zero on the delta.
- **Real concurrent smoke — no lost update:** two threads, each calling
  `Owl::Tasks::Internal::LabelWriter.add` 50 times with distinct labels on the
  SAME `TASK-0001`, ran to completion → final `labels` array had **100**
  entries, **50/50** from each thread (`a-labels=50/50 b-labels=50/50
  total=100 → SMOKE PASS`). Without serialization the interleaved
  read-modify-writes would drop entries (total < 100); the lock prevents it.
  This is the live counterpart to the unit `serialization (no lost update on
  stale read)` spec.

# Not run

- No `bin/owl step …` commands and no git mutations (forbidden / out of scope for
  this review). Coverage instead came from the real threaded smoke plus the
  unit spec, which together exercise the lock under genuine contention and on the
  exception path.
- No multi-PROCESS smoke (only multi-thread). The FileLock is a filesystem
  advisory lock keyed by a token file, so cross-process contention follows the
  same acquire/retry path the thread smoke and the `does not block a different
  task` / foreign-holder specs already cover; a process-level test was deemed
  redundant given the green file-lock unit coverage.

# Failures or blockers

None. All checks green; the smoke ran in a `Dir.mktmpdir` project that is removed
on block exit, so the repository working tree is left exactly as found (only the
intended TASK-0035 artifacts written).

# Residual risks

- `Deleter.call` does not lock the deleted task's own `task-<id>` before `rm_rf`
  (only the OTHER tasks it scrubs are locked), so a delete racing a live mutation
  of that same task is an inherent delete-while-in-use hazard, out of this task's
  lost-update scope. Low severity; flagged for a possible follow-up.
- A foreign lock held past the 10s acquire deadline surfaces a recoverable
  `:lock_held` error rather than blocking indefinitely — the same fail-safe the
  existing `IndexWriter` already uses; callers must surface it intelligibly.
