---
status: passed
summary: Brief now enforces the Requirement/Scenario grammar via required_patterns + require_scenarios + require_when_then; templates, grammar doc, and tests added; full suite green (1306 examples, 0 failures, 1 pending).
---

# Verification

## Summary

P2 makes the formal Requirement/Scenario grammar the enforced standard for the
`brief` artifact, reusing the pre-existing `required_patterns`/`PatternsChecker`
plus the P3 semantic keys (`require_scenarios`, `require_when_then`). No new
checker/runtime code; the only library change extends the artifact-type
*definition* validator + JSON schema so `required_patterns` accepts the object
form `{ pattern, type, level, description }` that the runtime `PatternsChecker`
already consumes (required to ship a custom, doc-pointing violation message).

Config + template + docs were changed in both the active `.owl/` copies and the
repo-root seed `artifacts/` copies. A canonical grammar reference doc was added
and linked from the brief and spec templates.

## Commands

- `bin/owl artifact-type validate brief --json` → `{"ok":true,"valid":true,...}`
- `bin/owl artifact-type validate spec --json` → `{"ok":true,"valid":true,...}`
- `bundle exec rspec spec/owl/validation/brief_grammar_spec.rb spec/owl/artifacts/internal/artifact_type_validator_spec.rb spec/owl/artifacts/template_skeletons_spec.rb spec/owl/integration/feature_workflow_full_cycle_spec.rb spec/owl/artifacts/api_spec.rb spec/owl/cli/integration/paths_via_local_reflection_spec.rb spec/owl/artifacts/backends/filesystem_spec.rb spec/owl/integration/schemas_wired_into_validators_spec.rb spec/owl/cli/init_seeded_templates_spec.rb` → 101 examples, 0 failures
- `bundle exec rspec` (full suite) → 1306 examples, 0 failures, 1 pending (exit 1)
- `bundle exec rubocop lib/owl/artifacts/internal/artifact_type_validator.rb spec/owl/validation/brief_grammar_spec.rb spec/owl/artifacts/internal/artifact_type_validator_spec.rb` → no offenses

## Outcomes

- **brief artifact type (active + seed)** — added `required_patterns`
  (`(?m)^###\s+Requirement:`, type regex, level error, doc-pointing
  description), `require_scenarios: true`, `require_when_then: true`. Existing
  `required_sections` + front matter unchanged. `forbid_empty_sections` NOT
  added. `artifact-type validate brief` passes.
- **brief default template (active + seed)** — `## Scenarios` now ships a formal
  `### Requirement:` (RFC 2119 SHALL) + `#### Scenario:` (WHEN/THEN/AND) plus a
  pointer to `docs/agents/31_Owl_Requirement_Scenario_grammar.md`. Instantiated
  copy validates `valid:true` (covered by `brief_grammar_spec` and
  `template_skeletons_spec`).
- **Grammar doc** — added `docs/agents/31_Owl_Requirement_Scenario_grammar.md`,
  matching the `2x_*` style; states enforcement by `required_patterns` +
  `require_scenarios` + `require_when_then` on both `brief` and `spec`.
- **Spec templates (active + seed)** — added a one-line pointer to doc 31.
- **Library change (definition validator + schema)** —
  `lib/owl/artifacts/internal/artifact_type_validator.rb` now accepts
  `required_patterns` entries as non-empty strings OR `{ pattern, ... }`
  mappings; `schemas/artifact.json` `required_patterns.items` updated to match.
  This was necessary: the design assumed the object form was usable in config,
  but the definition validator/schema previously allowed strings only. This is
  an internal checker, not `lib/owl/**/api.rb`, so the coverage gate is
  unaffected.
- **Fixture fixed** — `spec/owl/integration/feature_workflow_full_cycle_spec.rb`
  `brief_artifact` was prose-only (`- happy path`) and is completed against the
  real seeded brief via `init`; it would now fail the `complete` gate. Updated
  to include a `### Requirement:` + `#### Scenario:` (WHEN/THEN). No other
  brief-building spec needed changes — the validation/cli/steps specs all write
  their own minimal inline `.owl/artifacts/brief/artifact.yaml`, so they are
  insulated from the seed change.
- **New tests** — `spec/owl/validation/brief_grammar_spec.rb` drives the real
  seeded brief through `Owl::Validation::Api`: prose-only → blocking
  `missing_pattern`; Requirement without scenario → `requirement_without_scenario`;
  scenario WHEN-without-THEN → `scenario_missing_clause` (missing THEN);
  well-formed brief and the seeded default template → `valid:true`. Added
  required_patterns object-form cases to `artifact_type_validator_spec.rb`.
- **Self-introduced baseline failures resolved** — adding the object-form
  `required_patterns` to the seeded brief briefly broke 4 artifact-type
  validation specs (`api_spec:188`, `paths_via_local_reflection:164/310`,
  `backends/filesystem_spec:153`); the validator + schema extension makes the
  definition valid again and all 4 pass.

## Open follow-ups

- Pre-existing (NOT introduced here): `bundle exec rubocop
  spec/owl/integration/feature_workflow_full_cycle_spec.rb` reports one
  `RSpec/ExampleLength` offense [42/30] on the main walk example (line ~193). It
  exists on the clean file (confirmed by stashing my edit) and lives in an
  example I did not modify — my change only touched the `brief_artifact` helper.
  Left untouched to avoid out-of-scope refactoring; flagged for awareness.
- Pre-existing test-isolation bug (NOT mine): running the suite mutates the repo
  `README.md` in place (some spec writes to repo root instead of a tmp dir). I
  restored it via `git checkout README.md`. Worth a separate fix.
- Full-suite exit code 1 is solely the pre-existing `lib/owl/steps/api.rb`
  99.16% public-API coverage gap, unrelated to this task.
