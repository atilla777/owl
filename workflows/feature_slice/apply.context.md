# Purpose

Execute the checklist from the `plan` (or `tasks` / `patch_plan`) step — edit / create
code, run local checks, keep changes scoped to this task.

## When to use

After `plan` in `feature` / `feature_slice` / `hotfix` / `refactor` workflows.

## Inputs

- `tasks` artifact (the checklist).
- `spec` (and `design` if present) for context on intent.

## Outputs

- Repository changes scoped to the task. No KOS-side artifact — the work is in code.
