---
step_id: "brief"
applies_to_session_type: "discussion"
intended_audience: "orchestrator"
summary: "Synthesise a complete brief for a small change (quick workflow, autonomous)."
---

# Purpose

Capture the brief for a small, well-understood change: turn the task
request into a structured `Problem / Goal / Scenarios / Edge cases /
Acceptance criteria` document with the formal Requirement/Scenario
grammar, so `implement` works from one record of intent.

## When to use

First step of the `quick` workflow.

## Inputs

- Task id (from `owl task current --json` or explicit argument).
- The user's request: task title/description, chat history, ticket.

## Mode

Autonomous (`execution_mode: autonomous`). Unlike `feature`, the `quick`
workflow does **not** stop to interview the user on the brief step —
synthesise the brief directly from the task request and proceed. Still:

- Apply the project `brief` overlay completeness checklist before
  finalising; if a checklist item materially affects scope or
  correctness and the request leaves it ambiguous, that is a real
  blocker — stop and ask rather than guessing.
- Produce the formal `### Requirement:` / `#### Scenario:` blocks with
  `- WHEN` / `- THEN` (see
  `docs/agents/31_Owl_Requirement_Scenario_grammar.md`).
- Set front matter `status: approved` once the brief is complete; the
  artifact gate requires it.

If the change is large enough to need design, planning, or human
checkpoints, stop and recommend the `feature` workflow instead.
