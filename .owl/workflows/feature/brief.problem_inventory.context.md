---
step_id: "brief"
applies_to_session_type: "discussion"
applies_to_variants: ["problem_inventory"]
intended_audience: "orchestrator"
summary: "Inventory refactor problems (problem_inventory variant)."
---

# Purpose

Capture a refactor-driven brief: inventory the **problems** in a piece
of code or subsystem, justify which ones we will fix in this task, and
state acceptance criteria that confirm the refactor is done. Behaviour
must not change — that constraint is part of the brief.

## When to use

Invoked when `brief` runs with `variant: problem_inventory` (e.g.
`owl task create --workflow feature --variant brief=problem_inventory`
for a refactor task).

## Inputs

- Task id (from `owl task current --json` or explicit argument).
- The user's complaint or hypothesis: chat history, code-review notes,
  metrics, smell list, recent PRs that hit the area.

## Outputs

- `brief` artifact at `tasks/<TASK-ID>/brief.md` with front matter
  `status: approved` and `variant: problem_inventory`, structured as:

  - **Scope** — files, modules, or subsystem boundaries the refactor
    touches. Be explicit about what is in vs. out of scope.
  - **Problems** — numbered list of concrete issues (dead code,
    cyclic deps, leaky abstractions, hot-path allocations, etc.) with
    one-line evidence each.
  - **Priority** — which problems are addressed in this task vs.
    deferred, and why (effort, blast radius, dependency).
  - **Acceptance criteria** — observable conditions that confirm the
    refactor without behaviour change: test suite green, public API
    intact, no new warnings, benchmark within ±X%, etc.

## Mode

Interactive. Refuse to accept a brief whose only problem is "code is
ugly" — keep drilling until each listed problem has a one-line
evidence or metric. Behaviour-change requests belong in a
`variant: feature` task, not here. Questions follow the Owl skill
conventions (numbered options).
