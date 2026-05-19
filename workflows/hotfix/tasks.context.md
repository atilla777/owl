# Purpose

Decompose the patch_plan into ordered concrete tasks that `apply` will execute.
This is the task-checklist step from the hotfix workflow, not a generic
task-management skill.

## When to use

In `hotfix` workflow after `patch_plan`.

## Inputs

- `patch_plan` artifact.

## Outputs

- `tasks` artifact under `tasks/<TASK-ID>/tasks.md` — checklist for `apply`.

## Notes

Do not confuse with the `plan` step in feature/refactor workflows;
both create a `tasks` artifact but live in different workflows.
