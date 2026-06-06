---
status: approved
summary: "Add an RSpec example covering the cascade reopen_targets `task_workflow_missing` error branch so lib/owl/steps/api.rb reaches 100% line coverage, satisfying the project api-coverage rule and letting bundle exec rspec exit clean."
---

# Problem

`lib/owl/steps/api.rb` sits at 99.16% line coverage — one uncovered line (L185, the
`task_workflow_missing` error branch in `reopen_targets` when `cascade: true` and the task's
`task.yaml` has no `workflow.key`). This violates the project rule that every `lib/owl/**/api.rb`
is 100% line-covered (docs/agents/30) and makes the SimpleCov gate fail, so `bundle exec rspec`
exits non-zero even with zero test failures. It is pre-existing (introduced by commit ccb4a30),
not by recent work.

# Goal

Add one meaningful RSpec example that exercises the `task_workflow_missing` cascade branch, raising
`lib/owl/steps/api.rb` to 100% line coverage. Test-only; no production change.

# Scenarios

### Requirement: Cascade reopen on a workflow-less task errors clearly

The system SHALL return `task_workflow_missing` when `reopen` is called with `cascade: true` on a
task whose `task.yaml` has no `workflow.key`, and a test SHALL cover that branch.

#### Scenario: Cascade reopen without a workflow key
- WHEN `Owl::Steps::Api.reopen` runs with `cascade: true` on a task whose `task.yaml` has its
  `workflow.key` removed
- THEN it returns a `Result.err` with code `task_workflow_missing`
- AND `lib/owl/steps/api.rb` line coverage reaches 100%

# Edge cases

- The test must strip only the `workflow.key` (or the whole `workflow` mapping) from a real
  created task's `task.yaml`, leaving the rest valid, then reach `reopen_targets` via the cascade
  path (a completed/reopenable step).
- Non-cascade reopen is unaffected (returns early before `reopen_targets`).
- Must not change production code or any existing example's outcome.

# Acceptance criteria

- [ ] New RSpec example covers the `task_workflow_missing` cascade branch (asserts the error code).
- [ ] `lib/owl/steps/api.rb` reports 100% line coverage; `bundle exec rspec` exits 0.
- [ ] No production code changed; existing specs stay green; `bundle exec rubocop` clean (never `-A`).
