# Purpose

Produce a parent-level `design` with `Context / Decision / Alternatives
/ Risks / API` covering the cross-cutting choices that every child of
this composite must respect. The API section is the public surface
that publishes to `docs/` once the design ships.

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
  `status: approved`.

## Mode

Interactive. Children inherit this design's API contract — be precise
about it. Questions follow the Owl skill conventions (numbered options).

## Notes

Skipping turns the `merge_docs` step into a no-op for this composite.
