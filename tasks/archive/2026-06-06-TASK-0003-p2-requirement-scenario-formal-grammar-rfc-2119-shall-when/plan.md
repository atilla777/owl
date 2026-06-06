---
status: draft
summary: Config + template + docs checklist to mandate the Requirement/Scenario grammar on briefs, reusing required_patterns and P3 semantic keys, with fixture/spec updates and green gates. No new Ruby code.
---

# Goal

Make the formal grammar the enforced standard for `brief` and document it canonically, by
editing artifact-type config + templates + docs, updating any prose-only brief fixtures, and
keeping gates green. No new checker code.

# Checklist

1. **brief artifact type (active + seed)** — edit `.owl/artifacts/brief/artifact.yaml` AND the
   repo-root seed `artifacts/brief/artifact.yaml`, adding under `validation:`:
   - `required_patterns: [{ pattern: '(?m)^###\s+Requirement:', type: regex, level: error,
     description: 'Brief must define at least one formal "### Requirement:" ...' }]`
   - `require_scenarios: true`, `require_when_then: true`
   Keep `required_sections` + front matter as-is. Do NOT add `forbid_empty_sections`. Confirm
   `bin/owl artifact-type validate brief` passes.

2. **brief default template (active + seed)** — update `.owl/artifacts/brief/templates/default.md`
   AND `artifacts/brief/templates/default.md`: in the `## Scenarios` section put one
   `### Requirement: <name>` (RFC 2119 SHALL statement) + `#### Scenario: <name>` with
   `- WHEN` / `- THEN` / `- AND`, plus a one-line pointer to the grammar doc. Ensure an
   instantiated copy validates `valid:true`.

3. **Grammar reference doc** — add `docs/agents/31_Owl_Requirement_Scenario_grammar.md` defining
   Requirement (single RFC 2119 normative statement), Scenario (WHEN/THEN/AND), the
   one-Requirement-≥1-Scenario / Scenario-has-WHEN+THEN rules, and that it is enforced by the
   `required_patterns` + `require_scenarios` + `require_when_then` keys on `brief` and `spec`.
   Note it is shared by both artifact types.

4. **Link the grammar** — add a short pointer to doc 31 in the brief template and the spec
   template (`.owl/artifacts/spec/templates/default.md` + seed). If `docs/agents/` has an index
   file, add a one-line entry.

5. **Find & fix prose-only brief fixtures** — grep specs/fixtures that build a `brief` body
   inline (e.g. `spec/owl/validation`, `spec/owl/artifacts`, `spec/owl/cli/artifact_commands_spec`,
   any seeded-sources/template-skeleton suite). For each that will now fail: either add a minimal
   valid `### Requirement:`/`#### Scenario:` (WHEN/THEN) to the fixture, or, where the test's point
   is invalidity, assert the new violation. Enumerate them; do not leave the suite red.

6. **New tests** — add/extend a brief-validation spec proving: prose-only brief → `missing_pattern`
   (blocking); `### Requirement:` with no scenario → `requirement_without_scenario`; scenario with
   WHEN but no THEN → `scenario_missing_clause`; the updated default template → `valid:true`.
   Prefer driving through `Owl::Validation::Api` / `owl artifact validate`.

7. **Seed/active parity** — ensure the template-skeleton / seeded-sources suite still passes with
   both copies in sync (active `.owl/` and seed `artifacts/`).

8. **Gates** — `bundle exec rspec` green for touched areas + full-suite counts reported;
   `bundle exec rubocop` clean on changed files (never `-A`). (No `lib/owl/**/api.rb` touched
   expected → coverage gate unaffected beyond the pre-existing steps/api.rb note.)

# Smoke test

```
bin/owl artifact-type validate brief                 # passes with new keys
# Instantiate the template into a throwaway task and validate:
#   prose-only Scenarios -> missing_pattern (blocking)
#   add "### Requirement:" with no "#### Scenario" -> requirement_without_scenario
#   add scenario WHEN only -> scenario_missing_clause (THEN)
#   updated default template -> valid:true
bundle exec rspec spec/owl/validation spec/owl/artifacts spec/owl/cli spec/owl/skills
bundle exec rubocop .owl/artifacts spec  # plus any changed ruby; never -A
```
