---
status: draft
summary: Ordered checklist to implement semantic artifact validation (empty sections, placeholders, requirement↔scenario, WHEN/THEN) as opt-in validation keys with full RSpec coverage.
---

# Goal

Ship four opt-in semantic validation rules wired into `ArtifactRunner`, with shape
validation in the artifact-type validator and complete RSpec coverage, without changing
behaviour for any artifact type that does not declare the new keys.

# Checklist

1. **SectionScanner helper** — add `lib/owl/validation/internal/section_scanner.rb`
   (`module_function`): given a body string, return an ordered list of
   `{heading:, level:, body:}` segments where each segment's `body` is the text from the
   heading line to the next heading (any level) or EOF. Reuse `HEADING_RE` semantics from
   `SectionsChecker` (indent ≤3, `#+ `). Also expose a fenced-code-block line mask helper
   (track ```` ``` ````/`~~~` toggles) for the placeholders checker.

2. **EmptySectionsChecker** — `lib/owl/validation/internal/empty_sections_checker.rb`.
   `check(body, enabled)` → `[]` when falsy. For each scanned segment, strip whitespace,
   blank lines and `<!-- ... -->` comments; if remainder empty, emit
   `{type: 'empty_section', section: heading, level: 'error', description: ...}`.

3. **PlaceholdersChecker** — `lib/owl/validation/internal/placeholders_checker.rb`.
   `check(body, spec)` where `spec` is `true` (use default markers
   `%w[TODO TBD FIXME XXX]` + literal `<...>`) or an array of marker strings; `[]` when
   falsy/empty. Skip lines inside fenced code blocks (via SectionScanner mask). Case-sensitive
   substring match; one `{type: 'placeholder_text', section:, marker:, level: 'error'}` per
   matched line+marker, `section` = nearest preceding heading or `(document)`.

4. **ScenariosChecker** — `lib/owl/validation/internal/scenarios_checker.rb`.
   `check(body, enabled)` → `[]` when falsy. Find each `### Requirement ...` heading; a
   requirement spans to the next `### ` (level-3) heading or EOF; if it contains zero
   `#### Scenario` headings, emit
   `{type: 'requirement_without_scenario', requirement:, level: 'error'}`.

5. **WhenThenChecker** — `lib/owl/validation/internal/when_then_checker.rb`.
   `check(body, enabled)` → `[]` when falsy. For each `#### Scenario ...` block (spans to next
   `####`+/`###`+ heading or EOF), require a line matching `^[\s>*-]*\**\s*WHEN\b` and one
   matching `THEN`. For each missing keyword emit
   `{type: 'scenario_missing_clause', scenario:, missing: 'WHEN'|'THEN', level: 'error'}`.

6. **Wire into ArtifactRunner** — in `lib/owl/validation/internal/artifact_runner.rb#validate`,
   after the `PatternsChecker.check` line, read from `rules` (string-or-symbol):
   `forbid_empty_sections`, `forbid_placeholders`, `require_scenarios`, `require_when_then`;
   `require_relative` the four new modules + scanner; `violations.concat(...)` each. Keep
   ordering: front matter → sections → patterns → empty → placeholders → scenarios → when_then.

7. **Artifact-type shape validation** — in
   `lib/owl/artifacts/internal/artifact_type_validator.rb#validate_validation_block`, add:
   `forbid_empty_sections`/`require_scenarios`/`require_when_then` must be boolean when present;
   `forbid_placeholders` must be `true` or an array of non-empty strings when present. Emit
   `error_at('/validation/<key>', ...)` on mismatch. Leave unknown keys tolerated.

8. **Unit specs** — add under `spec/owl/validation/internal/`:
   `section_scanner_spec.rb`, `empty_sections_checker_spec.rb`, `placeholders_checker_spec.rb`,
   `scenarios_checker_spec.rb`, `when_then_checker_spec.rb`. Cover: positive emit, clean pass,
   off-by-default (falsy), nested headings, fenced-code exemption (placeholders), bullet/bold
   WHEN/THEN tolerance, requirement with deeper non-scenario headings → still zero scenarios.

9. **Integration spec** — extend `spec/owl/validation/api_spec.rb` (and/or
   `spec/owl/cli/artifact_commands_spec.rb`): an artifact type declaring the new keys produces
   the new blocking violations through `Owl::Validation::Api` / `owl artifact validate`; an
   artifact type without the keys is byte-for-byte unchanged in behaviour.

10. **Artifact-type validator spec** — extend the validator's spec to cover the new shape
    errors (boolean/array) and that valid declarations pass.

11. **Docs** — document the four keys in the artifact-type schema reference (wherever
    `required_sections`/`required_patterns` are documented; do NOT enable them on any seeded
    artifact type — that is Problem 2/P2's task).

12. **Quality gates** — `bundle exec rspec` green; `bundle exec rubocop` clean on changed files
    (NEVER `rubocop -A`); maintain 100% line coverage for any touched `lib/owl/**/api.rb`.

# Smoke test

```
# Build a throwaway artifact type with the new keys enabled and an artifact that violates each
# rule, then:
bundle exec owl artifact validate <TASK> <KEY> --json
# Expect violations[] to contain types: empty_section, placeholder_text,
# requirement_without_scenario, scenario_missing_clause, all level 'error', valid:false.

# Control: an artifact type WITHOUT the new keys validates identically to pre-change.
bundle exec rspec spec/owl/validation
bundle exec rubocop lib/owl/validation lib/owl/artifacts/internal/artifact_type_validator.rb
```
