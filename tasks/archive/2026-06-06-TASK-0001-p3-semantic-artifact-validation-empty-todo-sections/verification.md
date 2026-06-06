---
status: passed
summary: Semantic artifact validation (forbid_empty_sections, forbid_placeholders, require_scenarios, require_when_then) implemented as opt-in validation keys; full RSpec suite green and RuboCop clean on changed files.
---

# Summary

Implemented Problem 3 of the Owl-vs-OpenSpec comparison: four opt-in semantic
validation rules wired into `Owl::Validation::Internal::ArtifactRunner#validate`
next to `SectionsChecker`/`PatternsChecker`, plus shape validation for the new
keys in `Owl::Artifacts::Internal::ArtifactTypeValidator`.

New internal modules (`module_function`, mirroring existing checkers):

- `SectionScanner` — fence-aware heading parser: `headings`, `sections`
  (tight per-heading spans), and `code_line_mask`.
- `EmptySectionsChecker` — `forbid_empty_sections: true`; emits `empty_section`.
- `PlaceholdersChecker` — `forbid_placeholders: true | [strings]` (default
  markers `TODO TBD FIXME XXX <...>`); fenced-code lines exempt; emits
  `placeholder_text`.
- `ScenariosChecker` — `require_scenarios: true`; emits
  `requirement_without_scenario`.
- `WhenThenChecker` — `require_when_then: true`; bullet/bold-tolerant; emits
  `scenario_missing_clause`.

All four default to `level: 'error'` (blocking via `blocking_count`). Artifact
types that declare none of the keys behave exactly as before. No seeded artifact
type was changed. `schemas/artifact.json` documents the four keys under
`validation:` (`additionalProperties: true`, so unknown keys stay tolerated).

# Commands

- `bundle exec rspec spec/owl/validation spec/owl/artifacts/internal/artifact_type_validator_spec.rb`
  → `104 examples, 0 failures`.
- `bundle exec rspec` (full suite) → `1241 examples, 0 failures, 1 pending`.
- `bundle exec rubocop <14 changed lib + spec files>` → `14 files inspected, no offenses detected`
  (one `Performance/Detect` offense was fixed manually; `rubocop -A` was NOT used).

# Outcomes

- All gates pass: full RSpec suite green; RuboCop clean on every changed file.
- No `lib/owl/**/api.rb` file was touched, so the 100%-coverage-on-touched-api
  requirement is satisfied vacuously.
- Observed (pre-existing, unrelated): the full-suite report lists
  `lib/owl/steps/api.rb` at 99.16% line coverage. This file was not modified by
  this task; its coverage is a pre-existing project state.
- Tests added: unit specs for the scanner and each checker
  (`spec/owl/validation/internal/*`), validator shape-error spec
  (`spec/owl/artifacts/internal/artifact_type_validator_spec.rb`), and
  integration specs in `spec/owl/validation/api_spec.rb` (all four blocking
  violations surface through `Owl::Validation::Api`; a clean declaration passes;
  an artifact type without the keys is unchanged).
