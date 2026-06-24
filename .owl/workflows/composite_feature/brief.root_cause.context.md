---
step_id: "brief"
applies_to_session_type: "discussion"
applies_to_variants: ["root_cause"]
intended_audience: "orchestrator"
summary: "Find bug root cause for the composite task (root_cause variant)."
---

# Purpose

Capture a bug-driven brief for a **composite** task: a single root
cause that is large enough to need decomposition into multiple child
tasks. Document the symptoms, reproduction, and root cause, then leave
the work-splitting to the upcoming `decompose` step.

## When to use

Invoked when the composite `brief` runs with `variant: root_cause`
(typically: a production incident whose fix spans several
services/areas).

## Inputs

- Task id of the parent composite task.
- The incident report, post-mortem, or root-cause hypothesis.

## Outputs

- `brief` artifact at `tasks/<TASK-ID>/brief.md` with front matter
  `status: approved` and `variant: root_cause`, structured as:

  - **Symptoms** — user/system-visible failures, blast radius.
  - **Reproduction** — minimal way to trigger or observe the failure.
  - **Root cause** — the underlying cause, broad enough to motivate
    multiple child tasks. If still hypothetical, say so.
  - **Acceptance criteria** — the composite-level conditions that
    confirm the incident is resolved (each child will refine its own).

## Mode

Interactive. Aim for a brief broad enough to cover the whole composite
remediation but precise enough that `decompose` can produce
non-overlapping children, each with its own narrower brief. Questions
follow the Owl skill conventions (numbered options).

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
