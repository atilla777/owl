---
status: passed
summary: "bundle exec rspec → 1972 examples, 0 failures, 1 pending (pre-existing storage-contract), exit 0; README stayed clean (no checkout needed). rubocop on all six touched files → no offenses. Per-file line coverage: commit_push/api.rb 18/18 (100%, public-API gate), transaction.rb 68/68. Real-git smoke in mktemp repos confirmed: (a) `git add -A -- . :(exclude)tasks/TASK-BBB` stages lib/x.rb + tasks/TASK-AAA but NOT tasks/TASK-BBB; (b) empty exclude → plain `git add -A` stages everything; (c) `git diff --cached --quiet` exits 1 (ok=false) on a non-empty index and 0 (ok=true) on an empty one, so index_dirty?.ok ⇔ empty (NOT inverted); (d) no prefix collision — excluding tasks/TASK-001 leaves tasks/TASK-0010 staged. Ruby probe confirmed Tasks::Api.list returns String-keyed Hashes and other_active_task_dirs keeps the current task / drops it for a non-current id. No throwaway owl tasks created; tree left as found."
---

# Summary

Objective verification of TASK-0032 (scoped staging for `owl commit-push`). The
full suite is green and exits 0, the per-file public-API coverage gate holds for
`commit_push/api.rb`, RuboCop is clean on the delta, and the load-bearing git
behaviours (scoped `:(exclude)` pathspec; `git diff --cached --quiet` exit codes;
prefix-collision safety) were reproduced on **real git** in throwaway repos, not
just through mocks. Outcome: **passed**.

# Commands

```
bundle exec rspec
bundle exec rubocop lib/owl/commit_push/internal/git_runner.rb \
  lib/owl/commit_push/internal/transaction.rb \
  lib/owl/commit_push/api.rb \
  spec/owl/commit_push/git_runner_spec.rb \
  spec/owl/commit_push/api_spec.rb \
  spec/owl/commit_push/locking_spec.rb
git status --short README.md

# Real-git smoke #1 — scoped pathspec (in mktemp -d):
git init -q; mkdir -p tasks/TASK-AAA tasks/TASK-BBB lib
#   files: tasks/TASK-AAA/a.txt, tasks/TASK-BBB/b.txt, lib/x.rb
git add -A -- . ':(exclude)tasks/TASK-BBB' ; git diff --cached --name-only
git reset -q ; git add -A ; git diff --cached --name-only          # empty-exclude back-compat
git diff --cached --quiet ; echo $?                                 # non-empty index → 1
git reset -q ; git diff --cached --quiet ; echo $?                  # empty index → 0

# Real-git smoke #2 — prefix collision (in mktemp -d):
#   files: tasks/TASK-001/a.txt, tasks/TASK-0010/b.txt
git add -A -- . ':(exclude)tasks/TASK-001' ; git diff --cached --name-only

# Ruby probes (against the live repo):
ruby -e 'Owl::Tasks::Api.list(root:".") -> tasks key/class; first.keys classes'
ruby -e 'Owl::CommitPush::Api.other_active_task_dirs(root:".", task_id:"TASK-0032" / "TASK-9999")'

# Per-file line coverage from coverage/.resultset.json (commit_push/*).
```

# Outcomes

- **`bundle exec rspec`** → `1972 examples, 0 failures, 1 pending`, exit **0**.
  - The 1 pending is the pre-existing `Storage::Backends::Filesystem`
    concurrent-writes backend-contract spec, unrelated to this task.
  - Exit 0 ⇒ the `spec_helper` `at_exit` SimpleCov public-API gate did NOT trip.
    Overall line coverage 97.03%.
- **`git status --short README.md`** → clean; README was not dirtied, so **no
  `git checkout README.md` was needed** this run.
- **`bundle exec rubocop` (6 files)** → `6 files inspected, no offenses detected`
  (the two plugin-migration warnings are pre-existing `.rubocop.yml` notices,
  not offenses). Net-zero on the delta.
- **Per-file line coverage** (from `coverage/.resultset.json`):
  - `lib/owl/commit_push/api.rb` → **18/18 (100%)** — public-API gate satisfied.
  - `lib/owl/commit_push/internal/transaction.rb` → 68/68 (100%).
  - `lib/owl/commit_push/internal/git_runner.rb` → 22/30; the 8 missed lines are
    pre-existing/unused facade methods (`add_all`, `status_porcelain`) and the
    `rescue`/wrapper lines — not an `api.rb` file, so not gated.
- **Real-git smoke #1 (scoped pathspec):**
  - `git add -A -- . :(exclude)tasks/TASK-BBB` staged → `lib/x.rb`,
    `tasks/TASK-AAA/a.txt`; **not** `tasks/TASK-BBB/b.txt`. ✓
  - empty exclude (`git add -A`) staged all three including
    `tasks/TASK-BBB/b.txt` — back-compat confirmed. ✓
  - `git diff --cached --quiet`: exit **1** with a non-empty index, exit **0**
    with an empty index ⇒ `index_dirty?.ok` is `true` ⇔ index empty, NOT
    inverted. ✓
- **Real-git smoke #2 (prefix collision):** excluding `tasks/TASK-001` left
  `tasks/TASK-0010/b.txt` staged — pathspecs match on component boundaries, no
  over-exclusion. ✓
- **Ruby probes:** `Tasks::Api.list(root:'.')` → `ok=true`, `value[:tasks]` is an
  `Array` of Hashes whose keys are all `String` (so `task['id']` resolves).
  `other_active_task_dirs(root:'.', task_id:'TASK-0032')` → `[]` (current task
  kept), `task_id:'TASK-9999'` → `['tasks/TASK-0032']`. ✓

# Not run

- No live end-to-end `bin/owl commit-push` smoke (would mutate the real repo /
  push). Coverage instead: the `git_runner_spec.rb` real-git tests plus the two
  independent mktemp git smokes above exercise the load-bearing git primitives,
  and `api_spec.rb` pins the transaction wiring against stubbed facades.

# Residual risks

- `GitRunner#index_dirty?` is correct but reads against the grain (`ok=true`
  means *not* dirty); documented at both ends. Naming nit, no behavioural risk.
- Other tasks' code outside `tasks/` is still swept into the delivery commit —
  documented known limitation in the CHANGELOG.
