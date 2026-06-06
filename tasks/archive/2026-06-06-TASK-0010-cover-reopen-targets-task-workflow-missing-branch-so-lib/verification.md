---
status: passed
summary: "Added a focused unit test that exercises the defensive task_workflow_missing guard in reopen_targets; lib/owl/steps/api.rb now reports 100% line coverage and bundle exec rspec exits 0."
---

# Summary

Covered the single uncovered line in `lib/owl/steps/api.rb` (L185 — the `task_workflow_missing`
guard in `reopen_targets`). Investigation showed the line is **defensive and unreachable through
the public `reopen` path**: `reopen` resolves artifacts and inspects the task first, both of which
already reject a missing `workflow.key` (the same `task_workflow_missing` message is emitted from
nine modules). The guard can only fire if `Tasks::Api.inspect` returns a payload lacking
`workflow.key`. Rather than introduce the repo's first `# :nocov:`, added a unit test that stubs
`Tasks::Api.inspect` to that state and calls `reopen_targets` directly (it is a `module_function`),
asserting `task_workflow_missing`. This is a real test of the guard's contract.

# Commands

- `bundle exec rspec spec/owl/steps/reopen_spec.rb` → 8 examples, 0 failures (new example covers L185).
- Per-line coverage check: `lib/owl/steps/api.rb` L185 hits 0 → 1 after the test.
- `bundle exec rspec` (full) → **1416 examples, 0 failures, 1 pending; exit code 0**.
- Coverage report: no "Public API files below 100% line coverage" entries (was: `lib/owl/steps/api.rb: 99.16%`).
- `bundle exec rubocop spec/owl/steps/reopen_spec.rb` → no offenses (no `-A`).

# Outcomes

- `lib/owl/steps/api.rb` at 100% line coverage; the SimpleCov public-API gate passes and
  `bundle exec rspec` now exits 0 (previously exited 1 despite 0 failures).
- Test-only change: one example added to `spec/owl/steps/reopen_spec.rb`. No production code changed.
- All existing specs green; rubocop clean.
