---
step_id: "brief"
applies_to_session_type: "discussion"
applies_to_variants: ["problem_inventory"]
intended_audience: "orchestrator"
summary: "Inventory refactor problems for the composite task (problem_inventory variant)."
---

# Purpose

Capture a refactor-driven brief for a **composite** task: an inventory
of problems in a subsystem that is large enough to need decomposition
into multiple child refactors. List the problems, justify which are in
this composite, and leave per-child slicing to `decompose`.

## When to use

Invoked when the composite `brief` runs with
`variant: problem_inventory` (typically: a multi-week refactor across
several modules, e.g. extracting a domain, migrating a layer).

## Inputs

- Task id of the parent composite task.
- The user's complaint, architecture-review notes, smell catalogue,
  metrics, or recent PRs in the area.

## Outputs

- `brief` artifact at `tasks/<TASK-ID>/brief.md` with front matter
  `status: approved` and `variant: problem_inventory`, structured as:

  - **Scope** — subsystem boundary, modules touched, hard out-of-scope
    items.
  - **Problems** — numbered list, each with one-line evidence.
  - **Priority** — which problems this composite addresses vs. parks
    for later, and the reasoning.
  - **Acceptance criteria** — composite-level conditions confirming
    the refactor without behaviour change (suite green, API intact,
    benchmark within ±X%, no new warnings).

## Mode

Interactive. Drill into each "this is ugly" complaint until it has
concrete evidence. Decomposition into child tasks is the next step's
job; here we only need a shared map of the problem space. Questions
follow the Owl skill conventions (numbered options).
