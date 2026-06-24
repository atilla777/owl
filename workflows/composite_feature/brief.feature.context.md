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
