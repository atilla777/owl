---
status: draft
summary: Resolve the task ready/available command overlap, sync the config owl.version drift, and clear the current pointer when a task is deleted.
---

# Brief

## Problem

Three small UX/consistency warts:
1. `owl task available` and `owl task ready` are near-duplicates (both return the
   same runnable task with different schemas); `task ready` is referenced by no
   skill, reading as an orphan command — an agent has no guidance on when to use which.
2. `.owl/config.yaml` records `owl.version: 0.15.1` while the gem is 0.20.0 —
   stale version drift.
3. `owl task delete` does not clear `.owl/local/current.yaml`; deleting the current
   task leaves a dangling pointer (`owl task current` then returns `task_not_found`).

## Goal

The two "ready/available" commands have a documented, non-overlapping purpose (or
one is removed); the config version tracks the gem; deleting the current task
leaves no dangling current pointer.

## Scenarios

### Requirement: Delete clears current pointer
`owl task delete` SHALL clear the current pointer when it deletes the currently
pointed-to task.

#### Scenario: Delete the current task
- WHEN the current pointer is TASK-X and `owl task delete TASK-X --force` runs
- THEN `owl task current` reports no current task, not `task_not_found`

### Requirement: ready/available are disambiguated
The skills/docs SHALL state when to use `task available` vs `task ready`, or the
redundant command SHALL be removed.

#### Scenario: Agent needs a runnable task
- WHEN an agent asks "what can I work on?"
- THEN exactly one documented command answers, with no ambiguous duplicate

## Edge cases

- Removing `task ready` (if chosen) is a CLI-surface change — treat as minor/breaking
  per its public contract; prefer documenting over removing if any consumer relies on it.
- Config version sync should happen on `owl upgrade`, not silently on every command.

## Acceptance criteria

- `owl task delete <current>` leaves `owl task current` clean (covered by a spec).
- `.owl/config.yaml owl.version` matches `Owl::VERSION` after `owl upgrade`.
- ready/available disambiguated in owl-cli or one removed; rationale in CHANGELOG.
- Version bump + CHANGELOG.
