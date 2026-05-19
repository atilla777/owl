# Purpose

Execute the `plan` checklist — write code and tests together, run the
local verification harness, and record the outcome as a `verification`
artifact.

## When to use

After `plan` in the `feature` and `feature_slice` workflows.

## Inputs

- `plan` artifact (the checklist).
- `brief` and `design` for the intent and API surface.
- Project test/lint/smoke commands (project overlay can list them).

## Outputs

- Repository changes scoped to the task.
- `verification` artifact at `tasks/<TASK-ID>/verification.md` with
  `Summary / Commands / Outcomes` and front matter status
  `passed | failed | partial`.

## Mode

Autonomous. Write tests alongside production code (test-first
preferred). Re-run verification until status is `passed` or the
remaining failures are real blockers that need the user.
