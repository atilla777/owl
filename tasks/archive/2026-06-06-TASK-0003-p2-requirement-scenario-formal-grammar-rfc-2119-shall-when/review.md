---
status: resolved
summary: Adversarial self-review of P2 (Requirement/Scenario grammar on brief). No blocking or major issues found; active/seed parity exact, regex and 4 validation probes correct, validator/schema change minimal and sound, gates green. One pre-existing rubocop ExampleLength offense noted as out of scope.
---

# Code review

## Summary

P2 mandates the formal Requirement/Scenario grammar on the `brief` artifact type
purely through configuration plus a minimal definition-validator/schema extension,
updated templates, and a new canonical grammar reference doc. I reviewed it
adversarially: diffed every changed file, checked active/seed parity, independently
exercised the `required_patterns` regex against false-match prose, ran the four
mandated validation probes through the REAL seeded brief type, confirmed the
definition validator still rejects malformed `required_patterns` entries, and
re-ran the gate suites and rubocop. The change is correct, well-scoped, and green.
No new Ruby runtime code; only the artifact-type *definition* validator and JSON
schema were widened to accept the object form of `required_patterns` that the
runtime `PatternsChecker` already consumed.

## Findings

### F1 — Active/seed parity (severity: info — PASS)
`.owl/artifacts/brief/artifact.yaml` vs seed `artifacts/brief/artifact.yaml`,
both `templates/default.md`, and both spec `templates/default.md` are byte-for-byte
IDENTICAL (verified with `diff`). No drift between dogfood and `owl init` source.

### F2 — required_patterns regex correctness (severity: info — PASS)
`(?m)^###\s+Requirement:` correctly mandates a level-3 heading and does NOT
false-match: prose "this is a requirement:", a `#### Scenario:` line, `###Requirement:`
(no space), indented `  ### Requirement:`, or inline mid-line mentions. It does match
the heading the template emits and tolerates extra spaces. Verified by an independent
regex probe (7/7 expected) and by `brief_grammar_spec`.

### F3 — Four validation probes (severity: info — PASS)
Driven through the real seeded brief via `Owl::Validation::Api`
(`spec/owl/validation/brief_grammar_spec.rb`, 5 examples, 0 failures):
(a) updated default template instantiated verbatim → `valid:true`;
(b) prose-only Scenarios → blocking `missing_pattern` (level error);
(c) `### Requirement:` with no scenario → `requirement_without_scenario`;
(d) Scenario with WHEN only → `scenario_missing_clause` (missing THEN).
All four behave exactly as specified.

### F4 — Definition validator / schema change (severity: info — PASS)
`validate_required_patterns` accepts a non-empty string OR a `{ pattern: <non-empty
string>, ... }` mapping and rejects non-string/blank patterns. Bad `type`/`level`
enum values are caught by the widened JSON schema (`schemas/artifact.json`
`required_patterns.items` with `type`/`level` enums), confirmed by an ad-hoc probe
returning the two enum errors. `additionalProperties: true` keeps the schema lenient,
matching the hand validator. `bin/owl artifact-type validate brief` and `... spec`
both return `valid:true`. Spec coverage added in `artifact_type_validator_spec.rb`
(string array, object form, missing pattern, blank string). The change touches an
internal checker, not `lib/owl/**/api.rb`, so the public-API coverage gate is unaffected.

### F5 — forbid_empty_sections NOT on brief (severity: info — PASS)
`brief` adds only `required_patterns`, `require_scenarios`, `require_when_then`.
Neither `forbid_empty_sections` nor `forbid_placeholders` was added — correct: the
strict-composition note is honoured, and the template's `TODO` placeholders remain
legal (no `forbid_placeholders`).

### F6 — Fixture coverage claim (severity: info — PASS)
Only `feature_workflow_full_cycle_spec.rb` needed a grammar fix (its prose-only
`- happy path` brief, completed against the real seeded type via `init`, now carries
a `### Requirement:` + WHEN/THEN `#### Scenario:`). The edit landed in the
`FeatureWorkflowFullCycleFixtures` heredoc, not in any example body. All other
brief-touching specs write their own inline minimal `.owl/artifacts/brief/artifact.yaml`
and are insulated from the seed change. Verified empirically: the gate suites
(`spec/owl/validation artifacts integration cli skills`) are 545/545 green and the
full suite is 1306/0/1.

### F7 — Docs quality (severity: info — PASS)
`docs/agents/31_Owl_Requirement_Scenario_grammar.md` defines Requirement (single
RFC 2119 statement), Scenario (WHEN/THEN/AND), the two structural rules, and an
explicit enforcement table naming the keys for BOTH artifact types (`required_patterns`
on `brief`; `require_scenarios`/`require_when_then` on `brief` and `spec`). Both the
brief and spec templates link to the doc by correct relative path. Written in the
project's configured language (Russian), consistent with the other `docs/agents/2x_*`
files.

### F8 — Pre-existing rubocop ExampleLength (severity: minor — pre-existing, out of scope)
`feature_workflow_full_cycle_spec.rb:193` `RSpec/ExampleLength [42/30]` on the walk
example. The P2 edit did not touch that example (it modified the fixtures heredoc),
so the offense predates this task. Left untouched to avoid out-of-scope refactoring.

## Resolution

- F1–F7: PASS, no action required.
- F8 (minor): Acknowledged as pre-existing and out of scope; not introduced by P2.
  Recorded as an open follow-up, not a blocker.
- Gates re-run by the reviewer: gate subset 545 examples / 0 failures; full suite
  1306 examples / 0 failures / 1 pending (pre-existing concurrent-write pending +
  pre-existing `steps/api.rb` 99.16% public-API coverage gap → exit 1, unrelated to P2).
  rubocop on the four changed Ruby files: only the pre-existing F8 offense, no new
  offenses. The repo `README.md` was NOT dirtied during these runs (the known
  test-isolation bug did not trigger this time); no restore needed.

No blocking or major findings. Status: resolved.
