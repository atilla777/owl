# Purpose

Break the spec (and optional design) into an ordered tasks checklist so `apply` and
`verify` know exactly what to do.

## When to use

After `specify` (and optional `design`) in `feature` / `feature_slice` /
`refactor` workflows.

## Inputs

- `spec` artifact.
- `design` artifact when the previous step created one.

## Outputs

- `tasks` artifact under `tasks/<TASK-ID>/tasks.md` — a checklist of concrete actions to apply.
