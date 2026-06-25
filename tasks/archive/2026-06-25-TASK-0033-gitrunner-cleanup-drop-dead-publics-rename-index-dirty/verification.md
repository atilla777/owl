---
status: passed
summary: "grep -rn for the three old names (index_dirty?, status_porcelain, add_all) over lib/ + spec/ → 0 matches (exit 1), confirming no dangling code references; remaining hits are only CHANGELOG history + task/docs markdown. bundle exec rspec → 1972 examples, 0 failures, 1 pending (pre-existing storage-contract), exit 0; README stayed clean (no checkout needed). bundle exec rubocop on the 5 touched files → 5 files inspected, no offenses detected, exit 0. Per-file line coverage: commit_push/api.rb 18/18 (100%, public-API gate, unchanged), transaction.rb 68/68 (100%), git_runner.rb 20/26 (non-api, not gated; missed lines are unexercised facade wrappers). No git mutations, no owl step commands; tree left as found."
---

# Summary

Objective verification of TASK-0033 (GitRunner cleanup: drop dead `status_porcelain`/
`add_all`, rename `index_dirty?` → `index_clean?`). The decisive check — no
dangling references to the old names in runnable code — passes (grep over lib/ +
spec/ = 0). The full suite is green and exits 0, RuboCop is clean on the delta,
the `**/api.rb` coverage gate still holds (`commit_push/api.rb` untouched, 100%),
and README was not dirtied. Outcome: **passed**.

# Commands

```
grep -rn "index_dirty?\|status_porcelain\|add_all" lib/ spec/      # → 0 matches, exit 1
grep -rn "index_dirty?\|status_porcelain\|add_all" . --include=*.rb --include=*.md | grep -v "^./tasks/"
bundle exec rspec
bundle exec rubocop lib/owl/commit_push/internal/git_runner.rb \
  lib/owl/commit_push/internal/transaction.rb \
  spec/owl/commit_push/git_runner_spec.rb \
  spec/owl/commit_push/api_spec.rb \
  spec/owl/commit_push/locking_spec.rb
git status --short README.md
# Per-file line coverage from coverage/.resultset.json (commit_push/*).
```

# Outcomes

- **`grep` old names over `lib/` + `spec/`** → no output, exit **1** (zero
  matches). No dangling references to `index_dirty?`, `status_porcelain`, or
  `add_all` in any runnable code.
  - Broader grep (`.rb` + `.md`, excluding `tasks/`): the only remaining hits are
    `CHANGELOG.md` (the new 0.17.1 entry naming what was removed) and `docs/`
    markdown (TASK-0016/0032 historical design notes). No live `.rb` references.
    These are historical and intentionally not rewritten.
- **`bundle exec rspec`** → `1972 examples, 0 failures, 1 pending`, exit **0**.
  - The 1 pending is the pre-existing `Storage::Backends::Filesystem`
    concurrent-writes backend-contract spec, unrelated to this task.
  - Exit 0 ⇒ the SimpleCov public-API `at_exit` gate did NOT trip. Overall line
    coverage 97.05%.
- **`git status --short README.md`** → clean; README was not dirtied, so **no
  `git checkout README.md` was needed** this run.
- **`bundle exec rubocop` (5 files)** → `5 files inspected, no offenses detected`,
  exit **0** (the two plugin-migration lines are pre-existing `.rubocop.yml`
  notices, not offenses). Net-zero on the delta.
- **Per-file line coverage** (from `coverage/.resultset.json`):
  - `lib/owl/commit_push/api.rb` → **18/18 (100%)** — unchanged by this task,
    public-API gate satisfied.
  - `lib/owl/commit_push/internal/transaction.rb` → 68/68 (100%).
  - `lib/owl/commit_push/internal/git_runner.rb` → 20/26 (76.9%); not an `api.rb`
    file, so not gated. The missed lines are other unexercised facade wrappers,
    not the renamed predicate (which is covered by `git_runner_spec.rb`).

# Not run

- No live `bin/owl commit-push` end-to-end smoke (would mutate the repo / push)
  and no `bin/owl step` commands (out of scope for this review). Coverage instead:
  `git_runner_spec.rb` exercises `index_clean?` against real git; `api_spec.rb`
  and `locking_spec.rb` pin the transaction/lock wiring against stubbed facades;
  the rename is otherwise a body-identical no-op so the TASK-0032 verification of
  the underlying staging behavior still applies.

# Failures or blockers

None. All checks green.

# Residual risks

- The old method names survive only in historical CHANGELOG/docs/task prose
  (expected, intentionally untouched) — no runtime impact.
- `git_runner.rb` per-file coverage (76.9%) reflects long-standing unexercised
  facade wrappers, outside the gated `**/api.rb` set and unrelated to this change.
