---
status: approved
summary: "Add a scenario->test traceability convention (a `- TEST:` scenario annotation) and an `owl spec trace` coverage checker that reports/enforces every spec requirement has at least one scenario and every scenario links to at least one test, runnable at verification time."
---

# Problem

Owl can now state requirements and scenarios formally (P2/P3) and persist them in a living spec
(P1), but there is no link from a `#### Scenario` to the **test** that proves it. "Done" (a green
verification) therefore gives a weak guarantee that the implemented behaviour matches the spec:
acceptance criteria and tests are only loosely associated. The Owl-vs-OpenSpec comparison
(Problem 5) calls for traceability — each spec requirement → ≥1 scenario → ≥1 test — and a check
of that coverage at the `verification` step.

P3 already enforces requirement → scenario (`require_scenarios`) and scenario → WHEN/THEN
(`require_when_then`). The missing link is scenario → test, and a tool to report/enforce the whole
chain.

# Goal

Deliver the scenario→test link + a coverage checker:

- A lightweight, language-agnostic convention: each `#### Scenario:` carries one or more
  `- TEST: <reference>` lines naming the test(s) that prove it (a spec-file path, an example
  description, or an id).
- `owl spec trace <domain> [--strict] [--json]`: parse the spec, compute coverage —
  every requirement has ≥1 scenario, every scenario has ≥1 `- TEST:` — and report the chain;
  with `--strict`, exit non-zero / `ok:false` when any scenario is untraced.
- When a `- TEST:` reference resolves to a path under the project, optionally check the file
  exists and flag dangling references.
- Document the convention in the grammar reference and seed it in the spec template.

Out of scope (explicit, like P4): hard-wiring `owl spec trace` into the `feature` workflow's
`verification` step for every task — that is a deliberate workflow change. This task ships the
convention + checker + docs; the brief/design records the integration path (verification step runs
`owl spec trace --strict`).

# Scenarios

### Requirement: Every requirement must reach a scenario and a test

The checker SHALL report a requirement as covered only when it has ≥1 scenario and each of its
scenarios has ≥1 `- TEST:` reference.

#### Scenario: Fully traced spec passes
- WHEN every `### Requirement` has a `#### Scenario` and every scenario has a `- TEST:` line
- THEN `owl spec trace <domain> --json` returns `{ok:true, valid:true, coverage:{...},
  untraced:[]}`
- TEST: spec/owl/specs/trace_spec.rb (fully-traced example)

#### Scenario: Scenario without a test is flagged
- WHEN a scenario has no `- TEST:` line
- THEN trace lists it under `untraced` with its requirement + scenario names
- AND `owl spec trace --strict` returns `ok:false`
- TEST: spec/owl/specs/trace_spec.rb (untraced example)

### Requirement: Dangling test references are detected

The checker SHALL flag a `- TEST:` reference that looks like a project path but does not exist.

#### Scenario: Dangling path reference
- WHEN a `- TEST:` value is a path-like string (e.g. `spec/owl/foo_spec.rb`) that does not exist
  under the project root
- THEN trace reports it under `dangling` (non-path/description references are reported as
  `unverified`, not dangling)
- TEST: spec/owl/specs/trace_spec.rb (dangling example)

### Requirement: Trace is read-only and deterministic

The checker SHALL never modify the spec and SHALL produce a stable, ordered report.

#### Scenario: Trace does not write
- WHEN `owl spec trace <domain>` runs
- THEN no file under `specs/` is created or modified
- TEST: spec/owl/cli/spec_trace_command_spec.rb

### Requirement: Convention is documented and seeded

The system SHALL document the `- TEST:` convention and demonstrate it in the spec template.

#### Scenario: Template shows the link
- WHEN a contributor reads the grammar reference / spec template
- THEN the `- TEST:` annotation is defined and the seeded template's scenario carries one
- TEST: spec/owl/skills/template_skeletons_spec.rb (or the seed-parity suite)

# Edge cases

- A scenario with multiple `- TEST:` lines → all collected; covered if ≥1.
- `- TEST:` tolerant of bullet/indent/bold like WHEN/THEN (`- TEST:`, `* TEST:`, `  - TEST:`).
- A spec with zero requirements → trace returns covered/valid (vacuous), not an error.
- Missing spec / invalid domain → reuse P1 errors (`spec_not_found`, `invalid_domain`).
- Path-likeness heuristic for dangling detection must not false-flag prose (only treat values
  matching a path pattern, e.g. containing `/` and ending in a file extension, as paths).
- Trace must not require enabling a blocking validation key on the spec type (it is a
  verification-time report, not an authoring gate) — keep authoring-time spec validation unchanged.

# Acceptance criteria

- [ ] `- TEST:` scenario annotation convention defined in `docs/agents/31` and seeded in the spec
      template (active + seed copies kept in sync).
- [ ] `owl spec trace <domain> [--strict] [--json]` implemented: per-requirement/scenario coverage,
      `untraced`, `dangling`, `unverified` lists, summary counts; `--strict` flips `ok:false` on
      any untraced scenario.
- [ ] Read-only; deterministic ordered output; reuses P1 domain validation + errors.
- [ ] Trace logic in `Owl::Specs` (public api.rb → 100% line coverage) via storage roles, no raw
      File/Dir, no hard-coded paths.
- [ ] RSpec coverage: fully-traced pass, untraced flagged, dangling vs unverified, --strict
      behaviour, zero-requirements vacuous pass, read-only.
- [ ] `bundle exec rspec` green for touched areas; `bundle exec rubocop` clean (never `-A`).
