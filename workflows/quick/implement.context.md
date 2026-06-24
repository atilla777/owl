---
step_id: "implement"
applies_to_session_type: "execution"
intended_audience: "subagent"
summary: "Implement the change directly from the approved brief and record verification."
---

# Purpose

Implement the change described by the `brief` — write code and tests
together, run the local verification harness, and record the outcome as
a `verification` artifact. The `quick` workflow has no separate `plan`
step: the brief's Goal + Scenarios + Acceptance criteria are the spec.

## When to use

After `brief` in the `quick` workflow.

## Inputs

- `brief` artifact (intent, scenarios, acceptance criteria).
- Project test/lint/smoke commands (project overlay can list them).

## Outputs

- Repository changes scoped to the task.
- `verification` artifact at `tasks/<TASK-ID>/verification.md` with
  `Summary / Commands / Outcomes` and front matter status
  `passed | failed | partial`.

## Mode

Autonomous. Write tests alongside production code (test-first
preferred). Re-run verification until status is `passed` or the
remaining failures are real blockers that need the user. If the change
turns out to be larger than the brief implied (new design decisions,
cross-cutting impact), stop and recommend re-running under the `feature`
workflow rather than expanding scope here.
