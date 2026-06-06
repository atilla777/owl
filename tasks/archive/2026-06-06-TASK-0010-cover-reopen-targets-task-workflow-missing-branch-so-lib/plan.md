---
status: draft
summary: "Add one reopen_spec example covering the task_workflow_missing cascade branch, confirm steps/api.rb hits 100% and rspec exits 0."
---

# Goal

Cover `lib/owl/steps/api.rb` L185 (`task_workflow_missing` cascade branch) so the file reaches 100%
line coverage and `bundle exec rspec` exits 0. Test-only.

# Checklist

1. In `spec/owl/steps/reopen_spec.rb`, add an example: build a project + task (reuse the file's
   `setup_project`/helpers), strip `workflow.key` from the task's `task.yaml` (YAML load → delete
   key → dump), call `Owl::Steps::Api.reopen(root:, task_id:, step_id:, cascade: true)`, and assert
   `result.err?` with `code == :task_workflow_missing`. Mirror an existing cascade example for the
   reopenable-step preconditions.
2. `bundle exec rspec spec/owl/steps/reopen_spec.rb` green.
3. `bundle exec rspec` full → confirm `lib/owl/steps/api.rb` 100% (not in the below-100% list) and
   the process exits 0.
4. `bundle exec rubocop spec/owl/steps/reopen_spec.rb` clean (never `-A`).

# Smoke test

```
bundle exec rspec spec/owl/steps/reopen_spec.rb
bundle exec rspec ; echo "exit: $?"   # expect 0, no below-100% api files
bundle exec rubocop spec/owl/steps/reopen_spec.rb
```
