# Purpose

Read the parent's `brief` and `design`, produce `decomposition.md`, and
create matching child tasks (typically with the `feature_slice`
workflow), wired by `parent_id`.

## When to use

After `brief` (and optional `design`) in the `composite_feature`
workflow.

## Inputs

- `brief` artifact.
- `design` artifact when present.

## Outputs

- `decomposition` artifact at `tasks/<PARENT-ID>/decomposition.md`
  listing each child task, its scope, and how the children compose.
- New child tasks created via
  `owl task child create --parent PARENT-ID --workflow feature_slice
   --title "..."`.

## Mode

Interactive. The user confirms the slicing — children should be
non-overlapping and each independently shippable. Questions follow the
Owl skill conventions (numbered options).
