# Purpose

Self-review the parent's `design` and `decomposition` before the
parent commits and spawns the children to run independently. Catch
overlaps, gaps, and design-vs-slicing inconsistencies before they
multiply across children.

## When to use

After `decompose` in the `composite_feature` workflow.

## Inputs

- `brief` artifact (target).
- `design` artifact (cross-cutting decisions and API contract).
- `decomposition` artifact (slicing + per-child briefs).

## Outputs

- `review` artifact at `tasks/<PARENT-ID>/review.md` with front matter
  `status: open | resolved`. Body has `Summary / Findings /
  Resolution` sections.

## Mode

Autonomous. Run via a subagent acting as an independent reviewer with
this checklist:

1. Every acceptance criterion from `brief` is covered by at least one
   child slice.
2. Slices do not overlap in scope or in files they will touch.
3. Each slice is independently shippable (no hidden cross-slice
   dependency).
4. `design.API` is consistent with what the slices need; nothing in a
   child brief contradicts the parent design.
5. Each child brief is self-contained — a child agent reading only
   the child brief + parent design can act without re-asking the
   parent.

If any finding is unresolved, set `status: open` and surface it as a
blocker — the user is asked before `archive` runs. If everything
passes self-review, set `status: resolved` and continue autonomously.
