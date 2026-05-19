# Purpose

Produce the parent-level `design` with
`Context / Decision / Alternatives / Risks / API` covering the
cross-cutting choices that every child of this composite must respect.
This document is a working artifact that informs decomposition — it
does **not** publish to `docs/`. Each child republishes its own slice
of architecture from its own `design` via the child's `merge_docs`
step.

## When to use

After `brief` in the `composite_feature` workflow, when the children
need a shared architectural baseline. Skip with
`owl step skip TASK-ID design --reason "..."` when the composite is
just a fan-out with no cross-cutting decision.

## Inputs

- `brief` artifact.
- Codebase context for the modules touched by the composite.

## Outputs

- `design` artifact at `tasks/<TASK-ID>/design.md` with front matter
  `status: approved`. Archived with the parent task — no `docs/`
  publication from this step.

## Mode

Interactive. Children inherit this design's API contract — be precise
about it. Questions follow the Owl skill conventions (numbered
options).
