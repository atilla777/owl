---
step_id: "implement"
applies_to_session_type: "execution"
intended_audience: "subagent"
summary: "Implement the fix directly from the root-cause brief and record verification."
---

# Purpose

Implement the fix described by the `brief` — write the code change and its
covering tests together, run the local verification harness, and record the
outcome as a `verification` artifact. The `hotfix` workflow has no separate
`plan` step: the brief's root-cause finding, Goal, Scenarios, and Acceptance
criteria are the spec.

## When to use

After `brief` in the `hotfix` workflow.

## Inputs

- `brief` artifact (root cause, intent, scenarios, acceptance criteria).
- Project test/lint/smoke commands (project overlay can list them).

## Outputs

- Repository changes scoped to the fix — as small as the root cause allows.
- `verification` artifact at `tasks/<TASK-ID>/verification.md` with
  `Summary / Commands / Outcomes` and front matter status
  `passed | failed | partial`.

## Mode

Autonomous. Keep the change tightly scoped to the identified root cause and
add a regression test that fails without the fix. Re-run verification until
status is `passed` or the remaining failures are real blockers that need the
user. If the fix turns out to require design decisions or cross-cutting change,
stop and recommend re-running under the `feature` workflow rather than
expanding scope here.
