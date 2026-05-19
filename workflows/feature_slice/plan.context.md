# Purpose

Break the parent composite's `brief` and `design` (inherited via
`parent_id`) into an ordered checklist of concrete code changes scoped
to this slice.

## When to use

First step of the `feature_slice` workflow.

## Inputs

- Parent's `brief` artifact.
- Parent's `design` artifact when present.
- Slice's title and scope from `decomposition.md`.

## Outputs

- `plan` artifact at `tasks/<TASK-ID>/plan.md` — `Goal` paragraph plus
  a `Checklist` of `- [ ]` items, each naming a file path and the
  change.

## Mode

Autonomous. Inherit context from the parent — do not re-decide
architecture. If a slice cannot proceed without architectural input,
that is a blocker to escalate to the user.
