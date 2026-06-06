---
status: draft
summary: "Checklist to add the `- TEST:` scenario convention, a TraceChecker, and an owl spec trace CLI computing requirement->scenario->test coverage, with docs/template updates and 100% coverage on specs/api.rb."
---

# Goal

Ship the scenario->test traceability convention + `owl spec trace` coverage checker (read-only,
deterministic, `--strict`), document and seed the convention, with full tests and green gates.

# Checklist

1. **TraceChecker** — `lib/owl/specs/internal/trace_checker.rb` (`module_function`): given a parsed
   `SpecDocument` model, split each requirement body into `#### Scenario:` blocks (reuse
   `Owl::Validation::Internal::SectionScanner`; scenario spans to next `#### `/`### `/`## `/EOF),
   extract scenario `name` + `test_refs` via `/^[\s>*-]*\**\s*TEST:\s*(.+?)\s*$/`. Compute the
   `trace(model, root:)` report: per requirement+scenario status; lists `untraced` (no TEST),
   `dangling` (path-like ref, missing on disk), `unverified` (non-path ref); `summary` counts;
   `valid` = no untraced AND no dangling. Path-likeness: ref contains `/` AND matches `\.\w+$`;
   existence via `Owl::Storage::Api.exists?` against a project-root-resolved path. Zero requirements
   => vacuously valid. Deterministic document order.

2. **Specs::Api.trace** — add `trace(root:, domain:, strict: false)` to `lib/owl/specs/api.rb`
   (public; keep 100% coverage): slug-validate domain (SpecLocator), read spec (reuse show/locator;
   `spec_not_found`/`invalid_domain`), parse via `SpecDocument.parse`, run `TraceChecker.trace`,
   return report with `ok = strict ? valid : true`. No writes.

3. **CLI spec_trace** — `lib/owl/cli/internal/commands/spec_trace.rb` mirroring existing spec
   commands: positional `<domain>`, `--strict`, `--json`; JSON returns the report; non-JSON prints
   an ordered readable coverage summary. Wire into `dispatch_spec` (`lib/owl/cli/api.rb`); update
   `lib/owl/cli/internal/help_text.rb`.

4. **Grammar doc** — extend `docs/agents/31_Owl_Requirement_Scenario_grammar.md` with a `- TEST:`
   section: purpose, syntax, that ≥1 per scenario is required for full traceability, and that
   `owl spec trace --strict` (run at verification) enforces it. Note authoring-time validation is
   unchanged.

5. **Spec template (active + seed)** — add a `- TEST:` line to the seeded scenario in
   `.owl/artifacts/spec/templates/default.md` AND `artifacts/spec/templates/default.md`; keep them
   in sync and ensure the template still `owl spec validate`s clean (TEST line is an extra bullet,
   not a WHEN/THEN, so it must not break require_when_then).

6. **Tests** — `spec/owl/specs/internal/trace_checker_spec.rb`,
   `spec/owl/specs/trace_spec.rb` (Api), `spec/owl/cli/spec_trace_command_spec.rb`. Cover:
   fully-traced => valid; scenario without TEST => untraced + `--strict` ok:false; path-like
   missing ref => dangling; prose ref => unverified (still valid); multiple TEST lines; zero
   requirements => vacuous valid; read-only (no file created/modified); bullet/bold/indent TEST
   tolerance; scenario inside a code fence not miscounted; deterministic order.

7. **Seed parity** — ensure the template-skeleton / seed-parity suite passes with both template
   copies in sync.

8. **Gates** — `bundle exec rspec` green for touched areas + full-suite counts; confirm
   `specs/api.rb` 100% via simplecov; `bundle exec rubocop` clean on changed files (never `-A`).
   If the suite dirties `README.md` (known pre-existing isolation bug), `git checkout README.md`.

# Smoke test

```
# Seed a traced spec via the delta engine or template, then:
bin/owl spec trace demo --json            # -> coverage report, valid per TEST lines
bin/owl spec trace demo --strict --json   # ok:false if any scenario untraced
# Remove a scenario's TEST line -> untraced list grows, --strict ok:false
# Add a "- TEST: spec/owl/does_not_exist_spec.rb" -> dangling
# Add a "- TEST: described manually" -> unverified (still valid)
bundle exec rspec spec/owl/specs spec/owl/cli
bundle exec rubocop lib/owl/specs lib/owl/cli/internal/commands/spec_trace.rb lib/owl/cli/api.rb
# clean up throwaway specs/demo
```
