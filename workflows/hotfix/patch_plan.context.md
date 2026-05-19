# Purpose

Produce `patch_plan.md` with Контекст / План фикса / Тесты / Откат — the surgical plan
that `apply` will execute.

## When to use

In `hotfix` workflow after `issue`.

## Inputs

- `issue` artifact.

## Outputs

- `patch_plan` artifact under `tasks/<TASK-ID>/patch_plan.md`.
