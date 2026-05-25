---
step_id: "brief"
applies_to_session_type: "discussion"
applies_to_variants: ["feature"]
intended_audience: "orchestrator"
summary: "Collect feature requirements for the composite task (feature variant)."
---

# Purpose

Capture the brief for a composite (multi-child) task: turn a rough
request into `Problem / Goal / Scenarios / Edge cases / Acceptance
criteria` so the upcoming `decompose` step can carve clear children.

## When to use

First step of the `composite_feature` workflow.

## Inputs

- Task id of the parent composite task.
- The user's request: chat history, ticket, requirements paste,
  sketches.

## Outputs

- `brief` artifact at `tasks/<TASK-ID>/brief.md` with front matter
  `status: approved` once the user confirms the captured intent.

## Mode

Interactive. Aim for a brief broad enough to cover the whole composite
but specific enough that `decompose` can produce non-overlapping
children. Questions follow the Owl skill conventions (numbered options).
