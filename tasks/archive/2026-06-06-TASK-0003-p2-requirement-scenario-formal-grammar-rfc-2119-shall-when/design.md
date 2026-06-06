---
status: approved
summary: Enforce the grammar on `brief` purely via config — add required_patterns mandating `### Requirement:` and enable require_scenarios/require_when_then — update the shared default template, and add a canonical grammar reference doc linked from brief and spec. No new Ruby code.
---

# Context

P3 shipped semantic checkers (`require_scenarios`, `require_when_then`, `forbid_placeholders`,
`forbid_empty_sections`) as opt-in keys read by `ArtifactRunner.validate`. `required_patterns`
is a pre-existing validation key (`PatternsChecker`) supporting `{pattern, type, level,
description}` specs. P1 made the `spec` artifact type formal using the same keys. The `brief`
artifact type (`.owl/artifacts/brief/artifact.yaml` + repo-root seed `artifacts/brief/...`) still
validates only `required_sections` + front matter; its single `templates/default.md` is shared by
all variants (feature/root_cause/problem_inventory — they differ only by context file). So P2 is a
**configuration + content + docs** change: no checker code is needed.

# Decision

**1. `brief` artifact type — enforce the grammar via existing keys.** In both the active
`.owl/artifacts/brief/artifact.yaml` and the repo-root seed `artifacts/brief/artifact.yaml`
(`owl init` source), add to `validation:`:
- `required_patterns: [{ pattern: '(?m)^###\s+Requirement:', type: regex, level: error,
  description: 'Brief must define at least one formal "### Requirement:" (see the Requirement/
  Scenario grammar).' }]` — mandates ≥1 Requirement; anchored to a heading line so prose
  mentions of "requirement" do not match.
- `require_scenarios: true`, `require_when_then: true` — each Requirement well-formed.
- Do NOT add `forbid_empty_sections` (strict-composition note from TASK-0001).
Keep existing `required_sections` (Problem/Goal/Scenarios/Edge cases/Acceptance criteria) and
front matter unchanged.

**2. Update the shared `default.md` brief template** (active + seed copies) so the `Scenarios`
section contains one `### Requirement:` with a `#### Scenario:` (WHEN/THEN/AND) that validates
clean against the new rules, and a short inline pointer to the grammar reference. The template
must pass `owl artifact validate` end-to-end when instantiated.

**3. Canonical grammar reference doc.** Add `docs/agents/31_Owl_Requirement_Scenario_grammar.md`
(static agent memory, read directly) defining: `### Requirement: <name>` + a single RFC 2119
SHALL/MUST/SHOULD/MAY normative statement; `#### Scenario: <name>` with `- WHEN` / `- THEN` /
`- AND`; the rule "every Requirement has ≥1 Scenario; every Scenario has WHEN and THEN"; and that
this grammar is enforced by the `require_scenarios`/`require_when_then`/`required_patterns`
validation keys on both `brief` and `spec`. Link it from the brief template and the `spec` template
(P1) so both point at one definition. Add a one-line pointer in `docs/agents/` index if one exists.

**4. No spec-type change needed** — P1 already enabled `require_scenarios`/`require_when_then`/
`forbid_placeholders` on `spec`; P2 only adds the shared written grammar and the brief side. If the
`spec` template lacks a link to the new reference, add it for consistency.

# Alternatives

- **A new `require_requirements` checker** that mandates ≥1 Requirement — rejected: redundant;
  `required_patterns` already expresses "body must match this regex" with a custom message and a
  blocking level. Less code, reuses tested machinery.
- **Enforce only on the `feature` variant** — not possible at type granularity (validation is
  per artifact type, not per variant) and not worth a variant-aware validation redesign here;
  the mandate applies to all variants, and the template/grammar is written to fit bug/refactor
  briefs too.
- **Rename `Scenarios` → `Requirements`** in required_sections — rejected: churns every existing
  brief structure for no validation gain; the `Scenarios` section already houses Requirement/
  Scenario blocks by convention, and the grammar doc clarifies this.
- **Mandate via `forbid_empty_sections`** — rejected (strict composition with require_scenarios).

# Risks

- **Over-constraining non-feature briefs**: hotfix/refactor briefs must now carry a formal
  Requirement. Mitigated: those workflows are scaffolded/not-yet-seriously-used (per CLAUDE.md),
  and a bug/refactor requirement is expressible (`The system SHALL NOT <regression>` + WHEN/THEN).
  Templates demonstrate it.
- **required_patterns regex false negatives/positives**: anchor `(?m)^###\s+Requirement:` to a
  heading; covered by tests (prose "requirement" does not satisfy; a real heading does).
- **Breaking existing brief specs**: some fixtures/specs build minimal briefs without the grammar
  and will now fail validation. Update those fixtures to include a minimal valid Requirement, or
  assert the new violation where that is the point of the test. Enumerate and fix them.
- **Two copies (active `.owl/` + seed `artifacts/`)** drifting — update both; a template-skeleton
  suite already cross-checks seeds, so keep them in sync.

# API

No Ruby API changes; no new CLI. Surface affected:
- `brief` artifact type `validation:` gains `required_patterns` + `require_scenarios` +
  `require_when_then` (active + seed).
- `brief` `templates/default.md` updated (active + seed).
- New doc `docs/agents/31_Owl_Requirement_Scenario_grammar.md`; links added from brief and spec
  templates.
- Possible test-fixture updates where briefs were previously prose-only.
Behavioural change: `owl artifact validate <task> brief` and the brief `complete` gate now block
prose-only / malformed-grammar briefs. Documented as intended.
