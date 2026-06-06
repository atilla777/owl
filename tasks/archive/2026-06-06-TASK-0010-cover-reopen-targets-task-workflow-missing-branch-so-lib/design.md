---
status: approved
summary: "Add one example to spec/owl/steps/reopen_spec.rb that creates a task, removes its workflow key from task.yaml, calls Owl::Steps::Api.reopen with cascade:true, and asserts task_workflow_missing — covering the lone uncovered branch. No production change."
---

# Context

`reopen_targets(root:, task_id:, step_id:, cascade:)` in `lib/owl/steps/api.rb` (L177-198) returns
early `[step_id]` when `!cascade`; under `cascade` it reads the task payload and, when
`workflow.key` is absent, returns `Result.err(code: :task_workflow_missing)` (L185 — the one
uncovered line). `spec/owl/steps/reopen_spec.rb` already builds a project + task via the CLI and a
`write` helper; the existing examples cover the happy cascade path, so only the missing-workflow-key
branch is untested.

# Decision

Add a single example to `spec/owl/steps/reopen_spec.rb`:
1. Set up a project + task as the existing examples do, and advance a step to a state where reopen
   is valid (mirror an existing cascade example's preconditions).
2. Load the task's `task.yaml`, delete the `workflow` key (or its `key`), write it back.
3. Call `Owl::Steps::Api.reopen(root:, task_id:, step_id:, cascade: true)`.
4. Assert the result `err?` with `code == :task_workflow_missing`.
Run `bundle exec rspec` and confirm `lib/owl/steps/api.rb` is 100% (absent from SimpleCov's
below-100% list) and the process exits 0.

# Alternatives

- **`# :nocov:` around L185** — rejected: hides a real, reachable error path instead of testing it.
- **Test via the `owl step reopen --cascade` CLI** — viable but the direct `Owl::Steps::Api.reopen`
  call is the smallest, clearest cover for the branch; either reaches L185.

# Risks

- **Reaching the cascade branch requires a reopenable step** — mitigated by mirroring an existing
  cascade example's setup; if the workflow-key removal trips an earlier guard, strip only
  `workflow.key` (keep the `workflow` mapping) so `dig('workflow','key')` is nil at L184.
- **Brittleness to task.yaml shape** — mitigated by loading/dumping via YAML, not string edits.
- Test-only; no production behaviour change; coverage gate is the sole observable effect.

# API

No API change. One new RSpec example in `spec/owl/steps/reopen_spec.rb`. Observable effect:
`lib/owl/steps/api.rb` → 100% line coverage; `bundle exec rspec` exits 0.
