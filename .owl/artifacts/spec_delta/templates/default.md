---
domain: example
status: draft
---

# Spec Delta

A structural change to the `domain` spec above. Use any subset of the three
sections below — `## ADDED Requirements`, `## MODIFIED Requirements`,
`## REMOVED Requirements`. Each `### Requirement:` follows the formal
Requirement/Scenario grammar (see
`docs/agents/31_Owl_Requirement_Scenario_grammar.md`); every `#### Scenario:`
carries `- WHEN` / `- THEN` clauses and at least one `- TEST:` line so the
post-merge `owl spec trace --strict` gate passes.

`owl spec merge TASK-ID` reads `domain`, applies this delta to
`specs/<domain>/spec.md` via the P4 engine, then runs the P5 trace gate.

## ADDED Requirements

### Requirement: Example capability

The system SHALL provide the example capability, described by the scenario below.

#### Scenario: Example behaviour
- WHEN an actor performs the example action
- THEN the system produces the expected observable outcome
- TEST: spec/example/example_spec.rb
