---
step_id: "design"
applies_to_session_type: "discussion"
intended_audience: "orchestrator"
summary: "Produce a design when the brief leaves architectural choices open."
---

# Purpose

Produce a design with `Context / Decision / Alternatives / Risks / API`
when the brief leaves architectural choices open. The API section is the
public surface that publishes to `docs/` once the design ships.

## When to use

In `feature` / `composite_feature` workflows when the brief has more
than one credible implementation path. Skip with
`owl step skip TASK-ID design --reason "..."` when the path is obvious.

## Inputs

- `brief` artifact (Problem, Goal, Scenarios, Edge cases, AC).
- Codebase context for modules the design touches.

## Outputs

- `design` artifact at `tasks/<TASK-ID>/design.md` with front matter
  `status: approved` once the user confirms the chosen approach.

## Mode

Interactive. The `Alternatives` section is the load-bearing one — if
you cannot name a real alternative, the design likely belongs in the
brief instead. Questions follow the Owl skill conventions (numbered
options).

## Notes

This step is optional. If skipping, run
`owl step skip TASK-ID design --reason '...'` instead of
`owl step complete`. Skipping turns the `merge_docs` step into a no-op.
