---
status: resolved
summary: Adversarial self-review of P3 semantic artifact validation. Both quality gates pass (104 examples 0 failures; rubocop clean on 14 changed files). Backward-compat invariant verified by code and an integration test. No blocker/major findings; two nits accepted as-is.
---

# Summary

Reviewed the opt-in semantic artifact-validation change (Problem 3): five new
`module_function` checkers under `lib/owl/validation/internal/`
(`section_scanner`, `empty_sections_checker`, `placeholders_checker`,
`scenarios_checker`, `when_then_checker`), wiring in `artifact_runner.rb`, shape
checks in `artifact_type_validator.rb`, schema docs in `schemas/artifact.json`,
and unit + integration + validator specs.

The implementation faithfully matches the design. All four rules are genuinely
opt-in, default to `level: 'error'` (blocking via `blocking_count`), use stable
`type` strings, and emit violations whose shape matches the existing
`SectionsChecker`/`PatternsChecker` (`{type, ..., level: 'error', description}`).
Both quality gates pass and reproduce the implement claims exactly.

# Findings

## Gate verification (re-run by reviewer)

- `bundle exec rspec spec/owl/validation spec/owl/artifacts/internal/artifact_type_validator_spec.rb`
  → **104 examples, 0 failures**. Matches implement's claim.
- `bundle exec rubocop` on the 14 changed lib+spec files → **14 files inspected,
  no offenses detected**. Matches implement's claim. (Running rubocop over the
  whole `spec/owl/validation/internal/` directory surfaces 8 offenses, but all
  are in pre-existing untouched files `schema_check_spec.rb` /
  `schema_resolver_spec.rb`; correctly out of scope and left alone.)

## Scrutiny point 1 — backward-compat invariant — PASS

`ArtifactRunner#rule_value` returns `rules[key]` when the key is present, else
`rules[key.to_sym]`; an absent key yields `nil`, and every checker short-circuits
`return [] unless enabled` (placeholders via `markers_for` returning `[]` for
`nil`/`false`). A literal `false` correctly disables (not enables): unit specs
assert `check(..., false) == []`, and `validate_boolean` accepts `false`. The
integration spec "leaves behaviour unchanged for an artifact type that declares
none of the new keys" feeds an artifact with an empty section **and** a leftover
`TODO` under a type declaring only `required_sections`, and asserts
`valid: true` / `violations: []`. This is exactly the absent-keys + empty-section
+ TODO pass-through proof required. **Verified.**

## Scrutiny point 2 — design edge cases — PASS (covered by specs)

- Fenced-code exemption for placeholders: `placeholders_checker_spec` "exempts
  markers inside fenced code blocks"; `section_scanner_spec` covers both ``` and
  `~~~` fences plus unterminated fences.
- Nested headings / tight section spans: `empty_sections_checker_spec` "flags a
  parent heading that only holds subheadings"; `section_scanner_spec` "splits ...
  up to the next heading of any level".
- Requirement with only a deeper non-scenario subheading → zero scenarios:
  `scenarios_checker_spec` "counts deeper non-scenario headings as zero
  scenarios" and "ignores level-4 scenarios that belong to a later requirement".
- WHEN/THEN bullet/bold tolerance and case-sensitivity:
  `when_then_checker_spec` "tolerates leading bullets and bold markers", plus
  block-span boundary specs at level-4 and level-3 headings;
  `placeholders_checker_spec` "matches case-sensitively".

## Scrutiny point 3 — violation shape — PASS

All new violations carry `level: 'error'` (symbol key), matching
`SectionsChecker`. `blocking_count` reads `v[:level] || v['level']`, so they are
counted as blocking and flip `valid` to false. `type` strings are the stable
values named in the design: `empty_section`, `placeholder_text`,
`requirement_without_scenario`, `scenario_missing_clause`. The integration spec
asserts all four surface through `Owl::Validation::Api` with `valid: false` and
every violation `level == 'error'`.

## Scrutiny point 4 — validator shape-checks — PASS

`validate_semantic_keys` rejects non-boolean `forbid_empty_sections` /
`require_scenarios` / `require_when_then`, and rejects `forbid_placeholders` that
is neither boolean nor an array of non-empty strings. `artifact_type_validator_spec`
covers `'yes'`, `1`, `'no'`, `5`, and `['  ']` (blank entry) rejections plus the
valid boolean/array/`true` acceptances and unknown-key tolerance. Re-ran: green.

## Scrutiny point 5/6 — correctness probes — no bugs found

Checked fence toggling (`code_line_mask` correctly keeps an inner mismatched
fence masked and reopens state on matching close char), section-span off-by-one
(`start = heading.line + 1`, `finish = next heading.line` — verified by
`section_scanner_spec` exact-string assertions), `HEADING_RE` `\A...\z` anchors
correctly swallow the trailing newline via `\s*\z`, and the WHEN/THEN regex
`\A[\s>*-]*\**\s*(WHEN|THEN)\b` accepts `- WHEN`, `* THEN`, `> WHEN`, `**WHEN**`.
No off-by-one, anchor, or fence-toggle defect found.

## Nit 1 (accepted) — `forbid_empty_sections` applies to all headings

A title heading immediately followed by a subheading (tight span) is reported as
empty. This is an explicit, documented design decision ("chosen broad because
empty headings are never intended"), it is opt-in, and it is not enabled on any
seeded artifact type. No action.

## Nit 2 (accepted) — `require_scenarios` uses `\ARequirement\b` (word boundary)

A plural `### Requirements` heading would not be treated as a requirement,
whereas the design's informal `^###\s+Requirement` prefix-match would. Harmless
(the formal artifact convention is singular `### Requirement: ...`), opt-in, and
not enabled on any seeded type. No action.

# Resolution

- Gate re-runs (rspec 104/0, rubocop 14 files/0 offenses): confirmed — accepted.
- Backward-compat invariant (scrutiny 1): verified in code and by an integration
  test — accepted.
- Edge-case coverage (scrutiny 2), violation shape (3), validator shape-checks
  (4), correctness probes (5/6): all pass — accepted, no fix needed.
- Nit 1 (broad empty-section scope): accepted as documented design intent.
- Nit 2 (`Requirement` word boundary): accepted; harmless given the artifact
  convention.

No blocker or major finding remains open; no in-line fix was required. Setting
`status: resolved`.
