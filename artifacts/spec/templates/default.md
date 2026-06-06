---
status: draft
summary: One-line summary of the behaviour this domain specification governs.
---

# Spec

## Purpose

Describe the verifiable behaviour this domain owns. A spec is the persistent
source of truth for what the system SHALL do, expressed as Requirements with
concrete Scenarios that future changes are made against.

## Requirements

Use the formal Requirement/Scenario grammar — see
`docs/agents/31_Owl_Requirement_Scenario_grammar.md`. Each `### Requirement:`
states one RFC 2119 normative sentence and carries at least one
`#### Scenario:` with `- WHEN` / `- THEN` (and optional `- AND`) clauses, plus
one or more `- TEST:` lines naming the test(s) that prove it (checked by
`owl spec trace --strict`).

### Requirement: Example capability

The system SHALL provide the example capability, described by the scenarios
below.

#### Scenario: Example behaviour
- WHEN an actor performs the example action
- THEN the system produces the expected observable outcome
- TEST: spec/example/example_spec.rb
