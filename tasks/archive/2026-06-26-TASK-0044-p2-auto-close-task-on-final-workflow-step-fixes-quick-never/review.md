---
status: resolved
verdict: accepted
ready: true
summary: >-
  Generalized step-completion finalization (ArchiveFinalizer → TaskFinalizer)
  correctly auto-closes archive-less workflows to `done` and releases the
  current pointer, preserves the archive path, stays idempotent, and is fully
  spec-covered. Tests green (2040 examples, 0 failures); approved.
---

# Summary

TASK-0044 renames `Steps::Internal::ArchiveFinalizer` to `TaskFinalizer` and
broadens its single gate (`all_steps_terminal?`) so that completing the step
that makes every step terminal closes the task. The branch logic matches the
approved design exactly:

- Non-terminal status → `Tasks::Api.set_status(status: 'done')` + pointer reset.
- `archived` → pointer reset only, status preserved (NOT overwritten to `done`).
- Other terminal (`done`/`abandoned`) → no-op (false), which makes a re-complete
  of a `done` step a clean idempotent no-op (no task.yaml rewrite).

`Steps::Api.complete` and `idempotent_complete` thread `root:` through to the
finalizer (the latter gained a leading `root` param). The CLI `step complete`
command adds an additive optional `task_status` field, surfaced only when the
task is terminal after finalization. VERSION bumped 0.23.0 → 0.23.1 with a
matching CHANGELOG entry. Verified against brief/design/plan and Owl conventions.

# Findings

- **Correctness — branch logic (lib/owl/steps/internal/task_finalizer.rb:33-55):**
  none. The three-way branch is correct and reuses
  `Tasks::Internal::TaskStatuses::TERMINAL` (no duplicated status list). The
  step-terminal set `%w[done skipped]` is the documented step-level concept,
  intentionally distinct from the task-level TERMINAL constant.
- **Idempotency (lib/owl/steps/api.rb:90, 401-409):** none. Re-completing a
  `done` step routes through `idempotent_complete` → finalizer `done` branch →
  no-op; `spec/owl/steps/api_spec.rb` asserts byte-identical task.yaml
  (`File.binread` before/after) on the second complete. Verified.
- **FS-layering (task_finalizer.rb, step_complete.rb):** none. Status is set via
  `Tasks::Api.set_status` (per-task lock, TASK-0035) and reads go through
  `TaskReader` / `Tasks::Api.inspect`; no direct FS access from Internal/Api.
  Conforms to docs/agents/27_Owl_Ruby_code_architecture.md.
- **Additivity of `task_status` (step_complete.rb:58-78):** none. The field is
  computed by `terminal_task_status` and added only when the status is in
  `TaskStatuses::TERMINAL`; absent while in progress. `step_complete_task_status_spec`
  asserts both the absent (non-final step) and present (`done`) cases. JSON
  contract is backward-compatible (additive key only).
- **Edge cases from the brief:** none missing. Composite gate (gated terminal
  steps keep `all_steps_terminal?` false until children ready), skipped steps
  (counted terminal), and multiple leaf steps (criterion is "all steps terminal",
  not "specific id completed") are all handled by the shared gate; the design and
  api_spec cover them.
- **TASK-0043 interaction (severity: info, not blocking):** the updated tests in
  `next_spec`/`instructions_spec`/`feature_workflow_full_cycle_spec` are a
  legitimate behavior consequence, not a regression — see the report's TASK-0043
  assessment section. No change required.

# Resolution

All findings are "none" or informational. No code changes required. Verdict:
accepted (approved). The `verify: true` gate ran the full suite synchronously and
returned passing.

# Remediation

None required.

# Residual risks

- The `done` `action.kind` resolver branch is now only naturally reachable for an
  inconsistent state (workflow-complete + non-terminal status), which auto-close
  prevents. Coverage is retained via forced-status test cases. This is a
  defensive fallback, acceptable as-is.
- Optional future UX polish (out of scope, human decision): `owl next TASK-X` on a
  just-finished task now returns `task_terminal` (exit 1) rather than a friendly
  `done` advisory. The orchestrator's normal no-id/current-pointer loop is
  unaffected (falls through to `no_available_task` and stops cleanly).
