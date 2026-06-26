---
status: draft
summary: Remove dead `owl-step-run` references and fix owl-author to bind steps by session_type.
---

# Brief

## Problem

The executor skill was split into `owl-step-discussion` + `owl-step-execution`,
but `owl-step-run` (no longer on disk) is still referenced 9× across 5 files:
`skills/owl-cli/SKILL.md`, `skills/owl-init/SKILL.md`,
`skills/owl-orchestrator/SKILL.md`, `skills/owl-author/SKILL.md`,
`commands/owl-task-next.md`. The functionally dangerous one is
`skills/owl-author/SKILL.md:61`: the authoring skill auto-fills
`skill: owl-step-run` for every step it writes, so any workflow authored through
`/owl-author` today binds its steps to a non-existent skill.

## Goal

No skill or command references `owl-step-run`; `/owl-author` produces workflows
whose steps dispatch correctly by `session_type`.

## Scenarios

### Requirement: Authoring binds by session_type
The owl-author skill SHALL bind each authored step to `owl-step-discussion` when
`session_type: discussion` and `owl-step-execution` when `session_type: execution`,
never to `owl-step-run`.

#### Scenario: Author a new execution step
- WHEN a user authors a workflow step with `session_type: execution` via `/owl-author`
- THEN the emitted step carries `skill: owl-step-execution`

### Requirement: No dead references remain
The skills/commands tree SHALL contain zero references to `owl-step-run`.

#### Scenario: Grep after fix
- WHEN `grep -rn owl-step-run skills/ commands/` runs
- THEN it returns no matches

## Edge cases

- Custom workflows that explicitly name a different `owl-step-<x>` skill must be
  preserved verbatim, not rewritten.
- Version bump + CHANGELOG entry required (skills/** is consumer-materialized).

## Acceptance criteria

- `grep -rn owl-step-run skills/ commands/` → 0 matches.
- owl-author emits `session_type`-correct bindings (covered by a spec or manual check).
- `Owl::VERSION` bumped (patch) + CHANGELOG entry.
