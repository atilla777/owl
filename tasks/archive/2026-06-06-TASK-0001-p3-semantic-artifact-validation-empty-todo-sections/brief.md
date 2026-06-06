---
status: approved
summary: Add semantic artifact validation (empty/TODO sections, Requirement↔Scenario pairing, WHEN/THEN presence) on top of Owl's existing structural validation, as opt-in rule keys per artifact type.
---

# Problem

Owl artifact validation is purely **structural**. `Owl::Validation::Internal::ArtifactRunner`
runs only three checks: front-matter schema, `SectionsChecker`, `PatternsChecker`.
`SectionsChecker.check` verifies that a required heading *exists* — nothing about its
content. As a result:

- A section that is empty, or contains only a leftover `TODO —` placeholder, **passes**
  validation.
- A `### Requirement` with no `#### Scenario` under it **passes** validation.
- A `#### Scenario` missing a `WHEN` or `THEN` clause **passes** validation.

This is the cheapest, highest-ROI gap identified in the Owl-vs-OpenSpec comparison
(Problem 3): an artifact can be "valid" while being substantively incomplete, which makes
the `complete` gate a weak guarantee and pushes detection of hollow artifacts downstream
to humans.

# Goal

Extend the existing `validation` mechanism with **semantic** checks, expressed as new
opt-in rule keys in an artifact type's `validation:` block, without rebuilding the data
model and without changing the behaviour of any artifact type that does not opt in.

New rule keys (names indicative, finalised at design):

- `forbid_empty_sections: true` — every required section must have non-whitespace body content.
- `forbid_placeholders: [...]` — body must not contain leftover placeholder markers
  (e.g. `TODO —`, `TBD`, `<...>`), default list configurable.
- `require_scenarios: true` — every `### Requirement` heading must be followed by ≥1
  `#### Scenario` heading before the next `### Requirement` (OpenSpec `--strict` analogue).
- `require_when_then: true` — every `#### Scenario` block must contain both a `WHEN` and a
  `THEN` clause.

Checks reuse the existing violation shape (`{type, level, description, ...}`) and the
`error`/`warning` levels already honoured by `blocking_count`.

# Scenarios

### Requirement: Empty and placeholder sections are rejected

The validator SHALL fail an artifact whose required section is empty or contains only a
configured placeholder marker, when the artifact type opts into the corresponding rule.

#### Scenario: Empty required section
- WHEN an artifact type declares `forbid_empty_sections: true` and a required section has
  a heading but no non-whitespace body before the next heading or EOF
- THEN `owl artifact validate` returns a blocking `empty_section` violation naming the section
- AND the step `complete` gate refuses until the section is filled

#### Scenario: Leftover TODO placeholder
- WHEN an artifact type declares `forbid_placeholders` and a section body contains a
  configured marker such as `TODO —`
- THEN `owl artifact validate` returns a blocking `placeholder_text` violation naming the
  section and the matched marker

### Requirement: Requirements must carry at least one scenario

The validator SHALL fail an artifact in which a `### Requirement` heading has no
`#### Scenario` heading before the next `### Requirement` or EOF, when the artifact type
opts in.

#### Scenario: Requirement without a scenario
- WHEN an artifact type declares `require_scenarios: true` and a `### Requirement` block
  contains zero `#### Scenario` headings
- THEN `owl artifact validate` returns a blocking `requirement_without_scenario` violation
  naming the requirement heading

### Requirement: Scenarios must state WHEN and THEN

The validator SHALL fail a `#### Scenario` block that omits a `WHEN` or a `THEN` clause,
when the artifact type opts in.

#### Scenario: Scenario missing THEN
- WHEN an artifact type declares `require_when_then: true` and a `#### Scenario` block
  contains a `WHEN` line but no `THEN` line
- THEN `owl artifact validate` returns a blocking `scenario_missing_clause` violation
  naming the scenario and the missing clause

### Requirement: Existing artifact types are unaffected by default

The system SHALL leave validation behaviour for any artifact type that does not declare
the new rule keys exactly as it is today.

#### Scenario: Artifact type without opt-in
- WHEN an artifact type's `validation:` block declares none of the new semantic rule keys
- THEN `owl artifact validate` produces the same result it produces today (structural +
  front-matter only)
- AND no existing test for current artifact types changes outcome

# Edge cases

- A section whose body is only a Markdown comment (`<!-- ... -->`) or only whitespace/blank
  lines → treated as empty by `forbid_empty_sections`.
- Nested headings: a `### Requirement` followed by deeper headings (`#####`) that are not
  `#### Scenario` → still counts as zero scenarios.
- Placeholder markers appearing inside fenced code blocks — decide at design whether code
  fences are exempt (likely yes, to avoid false positives on example text).
- `WHEN`/`THEN` matching must tolerate list-bullet prefixes (`- WHEN`, `* WHEN`) and bold
  (`**WHEN**`); case-sensitivity decided at design.
- Rule keys must compose with existing `required_sections` / `required_patterns` without
  ordering surprises in the violations array.
- Warnings vs errors: each new rule should be expressible as `error` (blocking) — whether
  any default to `warning` is a design choice.

# Acceptance criteria

- [ ] New checker(s) wired into `ArtifactRunner.validate` alongside `SectionsChecker` and
      `PatternsChecker`, reading new keys from `descriptor[:validation]`.
- [ ] `forbid_empty_sections`, `forbid_placeholders`, `require_scenarios`, `require_when_then`
      implemented (final key names per design) and documented in the artifact-type schema.
- [ ] Each new rule is opt-in; artifact types that do not declare it behave exactly as today.
- [ ] `owl artifact validate` surfaces new violations with stable `type` values and correct
      `error` level so `blocking_count` and the `step complete` gate enforce them.
- [ ] RSpec coverage for every new violation path and the no-opt-in pass-through; existing
      validation specs stay green.
- [ ] `./run_tests.sh` green and `rubocop` clean on changed files.
- [ ] 100% line coverage maintained for any touched `lib/owl/**/api.rb`.
