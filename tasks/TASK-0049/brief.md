---
status: approved
summary: Align owl publish's step-status gate with the harness pre-start convention so a publishes-step that the orchestrator has already moved to running is accepted, matching commit-push.
---

# Brief

## Problem

The orchestrator's execution harness (`owl-step-execution`) pre-starts every
step with `owl step start` **before** running its body, advancing the step to
status `running`. Two terminal-ish operations then disagree about what status
the step should be in when they are invoked:

- `owl commit-push` (`lib/owl/commit_push/internal/transaction.rb`) expects the
  step to be `running` and self-completes it (`steps.complete` requires
  `running`) — correct under the pre-start convention.
- `owl publish` runs `Owl::Publish::Internal::StepGate`
  (`lib/owl/publish/internal/step_gate.rb`), whose
  `ACCEPTABLE_STATUSES = %w[ready done]` rejects a `running` step with
  `publish_step_not_ready` ("Step '<id>' for task '<id>' is not ready or done").

So a step that declares `publishes: true` (e.g. a `merge_docs` step) breaks: the
harness pre-starts it (`running`), then `owl publish` rejects it because
`running` is neither in the ready set nor `done`. The gate assumes the step is
still `ready` at publish time, but under the pre-start convention it never is.
This is a gate-ordering / precondition asymmetry between `publish` and
`commit-push`, not a workflow-authoring error.

The behaviour is currently unspecified: no spec covers `owl publish` against a
`running` step (`spec/owl/publish/api_spec.rb` only forces steps to `done`).

## Goal

Make `owl publish` accept a step that the harness has pre-started (`running`),
so a `publishes:`-bearing step runs end-to-end under the orchestrator's
pre-start convention, consistent with how `commit-push` already treats
`running`. Do not weaken the gate for genuinely not-yet-runnable steps
(`pending`/blocked steps that are neither ready, running, nor done must still be
rejected).

## Scenarios

### Requirement: Publish accepts a pre-started running step

The system SHALL allow `owl publish` to proceed when the publishing step's
stored status is `running`.

#### Scenario: Harness pre-starts the publishing step
- WHEN a step that declares `publishes: true` has been advanced to status
  `running` by `owl step start`
- THEN `owl publish TASK-ID` succeeds and copies the artifacts per the
  workflow's `publishes` rules
- AND it does not return `publish_step_not_ready`

### Requirement: Publish still rejects a not-runnable step

The system SHALL reject `owl publish` when the publishing step is neither
`ready`, `running`, nor `done`.

#### Scenario: Step is still pending and not ready
- WHEN the publishing step's stored status is `pending` and the step is not in
  the computed ready set (its requirements are unmet)
- THEN `owl publish TASK-ID` returns the `publish_step_not_ready` error
- AND the error details still report the current status and acceptable statuses

### Requirement: Publish remains idempotent for completed steps

The system SHALL continue to accept `owl publish` when the publishing step is
already `done`.

#### Scenario: Re-publish after completion
- WHEN the publishing step's stored status is `done`
- THEN `owl publish TASK-ID` succeeds exactly as before this change

## Edge cases

- **`ready` status unchanged** — a step that is genuinely `ready` (not yet
  pre-started) must still publish, so existing `mark_ready_chain`-style flows
  keep working.
- **Error details** — when rejection still occurs, the `acceptable_statuses`
  reported in the error details should reflect the updated whitelist so the
  message is not misleading.
- **No commit-push change** — `commit-push` already expects `running` and is
  out of scope; only `publish`'s gate is corrected. (The task title names both
  for context; the actual defect is in `publish`.)
- **Layering / FS access** — change stays inside `lib/owl/publish/**`, no new
  raw FS access paths; gate continues to read status from the task payload, not
  ad-hoc file reads.
- **Backward compatibility** — widening the accepted-status set is additive;
  no JSON response shape, schema, or seeded template changes. Per the
  Constitution this is a back-compat fix → patch version bump + CHANGELOG entry.

## Acceptance criteria

- `Owl::Publish::Internal::StepGate` accepts a step whose stored status is
  `running` (in addition to `ready` and `done`), and `owl publish` no longer
  returns `publish_step_not_ready` for a harness-pre-started step.
- A `pending`/not-ready step is still rejected with `publish_step_not_ready`,
  and the error details report the updated `acceptable_statuses`.
- An already-`done` step still publishes (idempotent), and a `ready` step still
  publishes — no regression to existing `spec/owl/publish/api_spec.rb` cases.
- New RSpec coverage in `spec/owl/publish/` asserts: (a) publish succeeds for a
  `running` step, (b) publish still fails for a `pending`/not-ready step.
- `Owl::VERSION` bumped (patch) and a `CHANGELOG.md` entry added in the same
  commit, per `docs/agents/23_Owl_Project_Constitution.md` §7.1.
- RuboCop and the affected specs are green.
