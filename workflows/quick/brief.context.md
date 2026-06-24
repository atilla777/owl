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
  `- WHEN` / `- THEN` (see the "Requirement/Scenario grammar" section
  below).
- Set front matter `status: approved` once the brief is complete; the
  artifact gate requires it.

If the change is large enough to need design, planning, or human
checkpoints, stop and recommend the `feature` workflow instead.

## Requirement/Scenario grammar

Express every scenario in the brief with the formal Requirement/Scenario
grammar (RFC 2119). Scenarios live under `## Scenarios` and are built from
these blocks:

```
### Requirement: <short behaviour name>

The system SHALL <one normative sentence>.

#### Scenario: <short case name>
- WHEN <trigger or precondition>
- THEN <expected observable outcome>
- AND <additional observable outcome — optional>
```

Rules:

- `### Requirement:` (heading level 3) states exactly **one** normative
  sentence with a single RFC 2119 keyword: `SHALL` / `MUST` (mandatory),
  `SHOULD` (recommended), `MAY` (allowed); `SHALL NOT` for a regression
  guard. One requirement = one sentence; multiple behaviours = multiple
  `### Requirement:` blocks.
- Every `### Requirement:` carries at least one `#### Scenario:`.
- Every `#### Scenario:` (heading level 4) has both a `- WHEN` and a
  `- THEN` line; `- AND` adds optional follow-on clauses. The `WHEN` /
  `THEN` / `AND` markers are UPPERCASE at the start of the list item.

These rules are enforced by the `brief` artifact validation
(`required_patterns` for `### Requirement:`, plus `require_scenarios` and
`require_when_then`) — a brief that violates them fails `owl artifact
validate` and the step `complete` gate.
