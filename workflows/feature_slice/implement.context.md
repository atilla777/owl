# Purpose

Execute the slice's `plan` checklist — write code and tests together,
run the local verification harness, and record the outcome as a
`verification` artifact.

## When to use

After `plan` in the `feature_slice` workflow.

## Inputs

- Slice's `plan` artifact.
- Parent's `brief` and `design` for intent and API surface.
- Project test/lint/smoke commands (project overlay can list them).

## Outputs

- Repository changes scoped to this slice.
- `verification` artifact at `tasks/<TASK-ID>/verification.md` with
  `Summary / Commands / Outcomes` and front matter status
  `passed | failed | partial`.

## Mode

Autonomous. Write tests alongside production code (test-first
preferred). Re-run verification until status is `passed` or remaining
failures are real blockers.
