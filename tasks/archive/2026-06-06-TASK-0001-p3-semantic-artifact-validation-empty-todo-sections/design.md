---
status: approved
summary: Add semantic checkers (empty sections, placeholders, requirement↔scenario pairing, WHEN/THEN) as new opt-in keys in the artifact `validation:` block, wired into ArtifactRunner next to SectionsChecker/PatternsChecker, with shape validation added to artifact_type_validator.
---

# Context

`Owl::Validation::Internal::ArtifactRunner.validate` (lib/owl/validation/internal/artifact_runner.rb)
reads `descriptor[:validation]` — the artifact type's `validation:` block, passed through
verbatim by `artifact_type_loader.rb:43` and `task_artifact_resolver.rb:178` — and runs
`SectionsChecker` and `PatternsChecker`. Violations carry `{type, level, description, ...}`;
`blocking_count` treats only `level: 'error'` as blocking; `step complete` re-runs the gate.

`artifact_type_validator.rb#validate_validation_block` currently shape-checks only
`required_sections` and `required_patterns` and does **not** reject unknown keys, so adding
new keys is backward-compatible: any artifact type that does not declare them is unaffected.

This is Problem 3 from the Owl-vs-OpenSpec comparison — the highest-ROI fix because the seam
already exists and no data-model change is required.

# Decision

Add semantic validation as **new opt-in keys** in `validation:`, each implemented by a small
checker module under `lib/owl/validation/internal/` and invoked from `ArtifactRunner.validate`
after the existing two checkers. The body passed to checkers is `fm_result[:body]` (front
matter stripped), same as today.

**Rule keys and semantics:**

1. `forbid_empty_sections: true|false` (default absent = off)
   - For each heading in the body, a section spans from that heading to the next heading of
     **any** level or EOF. A section is "empty" if, after stripping whitespace, blank lines,
     HTML comments (`<!-- ... -->`), the remaining body before the next heading is empty.
   - Applies to **all** headings present, not only `required_sections`, so a hollow optional
     section is still caught. (Design note: scope to required sections only is a possible
     narrowing; chosen broad because empty headings are never intended.)
   - Violation: `{type: 'empty_section', section, level: 'error'}`.

2. `forbid_placeholders: [strings]` (default absent = off; when `true`, use a built-in default
   list `['TODO', 'TBD', 'FIXME', 'XXX', '<...>']` matched as case-sensitive substrings on
   non-fenced lines)
   - Lines inside fenced code blocks (```` ``` ````/`~~~`) are **exempt** to avoid false
     positives on example text.
   - Markers match as substrings (`TODO —`, `TODO:`...). Each match yields one violation.
   - Violation: `{type: 'placeholder_text', section, marker, level: 'error'}` where `section`
     is the nearest preceding heading (or `'(document)'`).

3. `require_scenarios: true|false` (default off)
   - Every `### Requirement` heading (configurable depth/prefix; default `^###\s+Requirement`)
     must be followed by ≥1 `#### Scenario` heading before the next `### Requirement` or EOF.
   - Violation: `{type: 'requirement_without_scenario', requirement, level: 'error'}`.

4. `require_when_then: true|false` (default off)
   - Every `#### Scenario` block (default `^####\s+Scenario`) must contain both a `WHEN` and a
     `THEN` token. Matching is **case-sensitive** on the uppercase keyword, tolerant of leading
     list bullets and bold: regex `^[\s>*-]*\**\s*(WHEN|THEN)\b`. A scenario block spans to the
     next `####`+ Scenario, next `###`+ heading, or EOF.
   - Violation: `{type: 'scenario_missing_clause', scenario, missing: 'WHEN'|'THEN', level: 'error'}`.

All four default to **error** level (blocking); no warning-only mode in this task.

**Wiring:** in `ArtifactRunner.validate`, after the `PatternsChecker` line, read the four
keys from `rules` (string-or-symbol access like existing code) and concat each checker's
output. Checkers are pure `module_function` modules mirroring `SectionsChecker`/`PatternsChecker`.

**Schema:** extend `artifact_type_validator#validate_validation_block` to shape-check the new
keys (booleans for 1/3/4; array-of-strings-or-`true` for 2) so malformed declarations fail
`owl artifact-type validate` early. Unknown keys remain tolerated for forward-compat.

**Reuse heading parsing:** factor the heading regex/section-span logic into a shared helper
(`SectionScanner`) used by the new checkers; `SectionsChecker` may optionally adopt it but is
not required to change (keep its specs green).

# Alternatives

- **One mega-checker** reading all keys — rejected: harder to unit-test and violates the
  one-module-per-concern style already set by SectionsChecker/PatternsChecker.
- **Express everything via `required_patterns` regex** — rejected: requirement↔scenario
  pairing and per-section emptiness are structural/relational, not single-regex matchable;
  also yields opaque violation messages.
- **Make checks global/always-on** — rejected: would change behaviour of existing artifact
  types and break their specs; opt-in keys preserve backward compatibility (Requirement:
  "Existing artifact types are unaffected by default").
- **Default `forbid_placeholders` scanning inside code fences** — rejected: example artifacts
  legitimately show `TODO` inside fenced samples; fence exemption avoids false positives.

# Risks

- **False positives on placeholders** in legitimate prose (e.g. the word "todo" lowercase) —
  mitigated by case-sensitive, default uppercase-only marker list and fence exemption.
- **Section-span ambiguity** with nested headings — mitigated by the explicit "next heading of
  any level or EOF" rule; covered by unit tests including nested-heading fixtures.
- **WHEN/THEN matching** missing legitimate variants (e.g. "When" in prose) — accepted: the
  formal format mandates uppercase keyword lines; prose mentions are intentionally not matched.
- **Performance** — checkers are single-pass over the body; negligible vs current cost.
- **Coupling to brief format** — the new keys are opt-in per artifact type; this task does NOT
  enable them on any existing artifact type (that is Problem 2's job). It only ships the
  mechanism + tests with synthetic fixtures.

# API

No public Ruby API signature changes. Surface affected:

- `Owl::Validation::Internal::ArtifactRunner.validate` — internal, gains four conditional
  checker invocations.
- New internal modules: `Owl::Validation::Internal::{SectionScanner, EmptySectionsChecker,
  PlaceholdersChecker, ScenariosChecker, WhenThenChecker}` (final names at implement).
- `Owl::Artifacts::Internal::ArtifactTypeValidator` — gains shape validation for the four keys.
- New violation `type` values (stable strings): `empty_section`, `placeholder_text`,
  `requirement_without_scenario`, `scenario_missing_clause`.
- CLI contract unchanged: `owl artifact validate TASK-ID KEY --json` still returns
  `{ok, valid, violations[], artifact}`; only the set of possible `violations[].type` grows.
- Artifact-type YAML schema gains the four optional keys under `validation:`.
