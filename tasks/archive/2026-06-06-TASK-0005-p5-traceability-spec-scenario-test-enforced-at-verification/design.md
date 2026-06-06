---
status: approved
summary: "Add a `- TEST:` scenario annotation parsed by reusing P4's SpecDocument, an Owl::Specs::Internal::TraceChecker computing requirement->scenario->test coverage, and an owl spec trace CLI (read-only, --strict); document the convention in docs/agents/31 and seed it in the spec template."
---

# Context

P4 added `Owl::Specs::Internal::SpecDocument`, which parses a spec into requirement blocks
(`{name, heading, body}`) using the fence-aware `SectionScanner`. P3's checkers already enforce
requirement->scenario (`require_scenarios`) and scenario->WHEN/THEN (`require_when_then`). P1 gives
`Owl::Specs::Api` + `SpecLocator` (domain slug-validation, `spec_not_found`). What is missing is
the scenario->test link and a coverage report. The `- TEST:` line is a sibling of the existing
`- WHEN` / `- THEN` bullets inside a `#### Scenario:` block, so parsing reuses the same block model.

# Decision

**1. Convention.** Inside a `#### Scenario:` block, one or more `- TEST: <reference>` lines name
the test(s) proving the scenario. Reference is free text: a spec-file path
(`spec/owl/specs/foo_spec.rb`), an example description, or an id. Matching is tolerant of bullet/
indent/bold like WHEN/THEN: `/^[\s>*-]*\**\s*TEST:\s*(.+?)\s*$/`. Documented in
`docs/agents/31_Owl_Requirement_Scenario_grammar.md` and demonstrated in the spec template's
seeded scenario (active `.owl/artifacts/spec/templates/default.md` + seed
`artifacts/spec/templates/default.md`).

**2. Scenario-aware parse.** Extend the spec model so requirements expose their scenarios. Add
`Owl::Specs::Internal::TraceChecker` (`module_function`) that, given a parsed `SpecDocument`
model, splits each requirement body into `#### Scenario:` blocks (reuse SectionScanner; a scenario
spans to the next `#### `/`### `/`## ` or EOF) and extracts `name` + `test_refs:[...]` per scenario.
Keep this in the specs layer; do not modify P4's SpecDocument contract beyond an additive helper if
needed.

**3. Coverage computation.** `TraceChecker.trace(model, root:) -> {
  requirements: [{name, scenarios: [{name, test_refs, status}]}],
  summary: {requirements, scenarios, traced, untraced, dangling, unverified},
  untraced: [{requirement, scenario}],
  dangling: [{requirement, scenario, ref}],
  unverified: [{requirement, scenario, ref}],
  valid }`.
Per scenario: `untraced` if zero `- TEST:`; else for each ref classify — **path-like**
(heuristic: contains `/` AND matches a file-extension tail like `\.\w+$`) → check existence under
the project root via `Storage::Api.exists?`; missing → `dangling`, present → traced. Non-path refs
→ `unverified` (counts as traced for `valid`, but surfaced so humans can audit). `valid` =
no `untraced` AND no `dangling`. A spec with zero requirements is vacuously `valid`. Output lists
are ordered by document order (deterministic).

**4. Api + CLI.** `Owl::Specs::Api.trace(root:, domain:, strict: false)` → resolves+reads the spec
(reuse `show`/locator; `spec_not_found`/`invalid_domain` reused), parses, runs TraceChecker,
returns the report with `ok` = `strict ? valid : true`. CLI `spec_trace.rb` under
`cli/internal/commands/`: positional `<domain>`, `--strict`, `--json`; wired into `dispatch_spec`;
non-JSON prints a readable coverage summary. Read-only — no writes anywhere. Update HELP_TEXT.

**5. Verification-step integration (documented, not wired).** Record in the design + grammar doc
that the `feature` workflow's `verification` step should run `owl spec trace <domain> --strict`
and fail on gaps. Wiring it into the workflow YAML (which would require each task to declare its
spec domain) is deferred — same rationale as P4 (avoid changing every task's flow mid-stream).

# Alternatives

- **Tests declare coverage (RSpec metadata `scenario:`) and trace scans Ruby files** — rejected:
  language-specific, ties Owl to RSpec, and requires parsing/executing test files; the `- TEST:`
  annotation in the spec is language-agnostic and lives with the contract.
- **A new blocking validation key `require_scenario_tests` on the spec type** — rejected:
  traceability is a verification-time report, not an authoring gate; forcing a `- TEST:` at
  authoring time blocks drafting specs before tests exist. `owl spec trace --strict` is the gate,
  invoked when appropriate (verification), keeping authoring validation unchanged.
- **Require every ref to be an existing path** — rejected: refs are legitimately descriptions/ids
  early on; classify into traced/unverified/dangling instead of a hard fail, and let `--strict`
  decide on untraced+dangling only.
- **Wire into verification now** — rejected (scope; mirrors P4).

# Risks

- **Scenario-split boundary bugs** (a scenario swallowing the next, or `#### Scenario` inside a
  code fence) — mitigated by reusing the fence-aware SectionScanner and adversarial fixtures.
- **Path-likeness false positives/negatives** — mitigated by a conservative heuristic (needs `/`
  and an extension) + tests for prose refs (→ unverified) vs real paths (→ traced/dangling).
- **Determinism** — output strictly in document order; a determinism/order test.
- **Seed/active template + grammar drift** — update both template copies + the doc; the seed-parity
  suite guards it.
- **api.rb coverage** — `lib/owl/specs/api.rb` public → exercise `trace` ok/err + strict/non-strict
  through the Api/CLI path.

# API

New public: `Owl::Specs::Api.trace(root:, domain:, strict: false) -> Result` (report hash above;
`ok` reflects strict). New internal: `Owl::Specs::Internal::TraceChecker`. New CLI: `owl spec
trace <domain> [--strict] [--json]`. Errors reused: `invalid_domain`, `spec_not_found`. Docs:
`docs/agents/31` gains a `- TEST:` section; spec template (active+seed) seeds a `- TEST:` line.
`lib/owl/specs/api.rb` requires 100% line coverage. No change to authoring-time spec validation.
