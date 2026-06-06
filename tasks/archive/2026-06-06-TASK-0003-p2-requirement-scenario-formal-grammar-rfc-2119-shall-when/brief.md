---
status: approved
summary: Mandate the formal Requirement/Scenario grammar in briefs (and align specs), reusing P3 semantic keys plus required_patterns to enforce ≥1 well-formed Requirement, with updated templates and a canonical grammar reference doc.
---

# Problem

Owl's `brief` artifact keeps user scenarios as **free prose / checkboxes**: the `Scenarios`
section has no required structure, so the same brief is interpreted differently across runs and
agents, producing non-deterministic downstream design/plan/implementation. The Owl-vs-OpenSpec
comparison (Problem 2) calls for a formal grammar — `### Requirement` / `#### Scenario` with
RFC 2119 normative statements and WHEN/THEN clauses — so each scenario reads as an unambiguous,
testable contract.

P3 already shipped the *checkers* (`require_scenarios`, `require_when_then`) and P1 made the new
`spec` artifact formal. The `brief` artifact has not yet adopted the grammar, and there is no
canonical written definition of the format for humans and agents to follow.

# Goal

Make the formal Requirement/Scenario grammar the **enforced standard** for `brief` artifacts and
document it canonically, reusing existing mechanisms (no new checker code):

- Mandate ≥1 well-formed `### Requirement:` with a `#### Scenario:` in every brief.
- Enforce each Scenario carries WHEN and THEN.
- Update the brief template so a fresh brief demonstrates and passes the grammar.
- Publish one canonical grammar reference (narrative) that `brief` and `spec` both point to.

# Scenarios

### Requirement: Briefs must contain a well-formed Requirement

The system SHALL reject a `brief` that has no `### Requirement:` heading, reusing the existing
`required_patterns` validation mechanism.

#### Scenario: Prose-only brief is rejected
- WHEN a brief's Scenarios section is free prose with no `### Requirement:` heading
- THEN `owl artifact validate <task> brief` reports a blocking `missing_pattern` violation
- AND the step `complete` gate refuses until a formal Requirement is added

### Requirement: Each Requirement must have a Scenario, each Scenario WHEN+THEN

The system SHALL enforce that every `### Requirement` in a brief has ≥1 `#### Scenario`, and
every Scenario states WHEN and THEN, by enabling the P3 semantic keys on the `brief` type.

#### Scenario: Requirement without scenario is rejected
- WHEN a brief contains `### Requirement:` with no `#### Scenario` beneath it
- THEN validation reports a blocking `requirement_without_scenario` violation

#### Scenario: Scenario missing THEN is rejected
- WHEN a brief Scenario has a WHEN line but no THEN line
- THEN validation reports a blocking `scenario_missing_clause` violation (missing THEN)

### Requirement: Fresh briefs validate against the grammar

The system SHALL ship a brief template that already satisfies the mandated grammar.

#### Scenario: New brief from template
- WHEN a brief is created from the updated default template
- THEN it validates `valid:true` without edits
- AND it visibly demonstrates the `### Requirement` / `#### Scenario` / WHEN/THEN shape

### Requirement: One canonical grammar definition exists

The system SHALL provide a single written reference for the Requirement/Scenario grammar that
brief and spec both reference.

#### Scenario: Grammar reference present
- WHEN a contributor looks for the format rules
- THEN a canonical reference document defines Requirement, Scenario, RFC 2119 keywords, and
  WHEN/THEN, and is linked from the brief and spec artifact guidance

# Edge cases

- All brief variants (feature, root_cause, problem_inventory) share the single `default.md`
  template and the single `brief` artifact type, so the mandate applies to every variant —
  the template must express the grammar in a way that fits bug/refactor briefs too (a bug
  scenario is naturally WHEN <trigger> THEN <wrong behaviour>).
- `required_patterns` is a regex/ substring check; the pattern must match `### Requirement:`
  tolerant of trailing text, and must not false-match prose mentioning the word "requirement".
- Enabling the mandate affects only briefs validated/created AFTER the change; already-archived
  briefs are not retro-validated.
- Must not enable `forbid_empty_sections` on brief (would force prose under each Requirement —
  the strict-composition note from TASK-0001 review).
- The grammar must stay consistent between `brief` and `spec` (same keywords, same checkers).

# Acceptance criteria

- [ ] `brief` artifact type enables `require_scenarios: true` + `require_when_then: true` and adds
      a `required_patterns` entry mandating `### Requirement:` (with a clear violation message).
- [ ] `brief` does NOT enable `forbid_empty_sections`.
- [ ] `default.md` brief template updated to use the grammar and validates `valid:true`.
- [ ] Canonical grammar reference doc added and linked from brief + spec guidance.
- [ ] Tests: prose-only brief fails (missing_pattern), requirement-without-scenario fails,
      scenario-missing-THEN fails, updated template passes; existing brief-related specs updated
      for the new rules.
- [ ] `bundle exec rspec` green for touched areas; `bundle exec rubocop` clean on changed files
      (never `-A`).
