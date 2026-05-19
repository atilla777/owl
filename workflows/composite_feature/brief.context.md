# Purpose

Capture the initial brief for a new Owl task: turn a rough request into a structured
Контекст / Цель / Acceptance criteria document so later steps have a stable foundation.

## When to use

First step of `feature` and `composite_feature` workflows when a task needs a written
intent record before specifying the solution.

## Inputs

- Task id (from `owl task current --json` or explicit argument).
- Human intent: chat history, ticket, requirements paste.
- Any context the requester already shared (links, sketches, conversations).

## Outputs

- `brief` artifact under `tasks/<TASK-ID>/brief.md` with sections Контекст / Цель / Acceptance criteria.
