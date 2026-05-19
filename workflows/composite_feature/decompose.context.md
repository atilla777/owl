# Purpose

Read the brief/spec/design of a `composite_feature` and produce `decomposition.md`
plus matching child tasks (typically `feature_slice` workflow), wired by `parent_id`.

## When to use

Inside `composite_feature` after `specify` (or optional `design`).

## Inputs

- `spec` artifact.
- `design` artifact (optional).

## Outputs

- `decomposition` artifact under `tasks/<PARENT-ID>/decomposition.md`.
- New child tasks (created via
`owl task child create --parent PARENT-ID --workflow feature_slice --title "..."`).
