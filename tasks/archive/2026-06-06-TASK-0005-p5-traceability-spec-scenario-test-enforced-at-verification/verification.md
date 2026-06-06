---
status: passed
summary: "P5 scenario->test traceability shipped: TraceChecker + Owl::Specs::Api.trace + owl spec trace CLI, docs/template seeded; specs/api.rb at 100% coverage, full suite 1372 examples 0 failures, rubocop clean."
---

# Summary

Delivered the scenario->test traceability convention and the `owl spec trace`
coverage checker per plan items 1-7:

- `lib/owl/specs/internal/trace_checker.rb` — fence-aware scenario split (reuses
  `SectionScanner`), `- TEST:` extraction, requirement/scenario/ref
  classification (untraced / dangling / unverified / traced), deterministic
  document-order report; `valid` = no untraced AND no dangling; zero
  requirements => vacuously valid.
- `Owl::Specs::Api.trace(root:, domain:, strict:)` — read-only; reuses
  SpecLocator domain slug-validation + `spec_not_found` / `invalid_domain`;
  `ok = strict ? valid : true`.
- CLI `owl spec trace DOMAIN [--strict] [--json|--no-json]` wired into
  `dispatch_spec`; help text updated; exit code follows `ok`.
- Grammar doc `docs/agents/31` extended with a `- TEST:` section; spec template
  (active `.owl/artifacts/spec/templates/default.md` + seed
  `artifacts/spec/templates/default.md`) seed a `- TEST:` line, both in sync and
  still validating clean.

Scope honoured: `owl spec trace` is NOT wired into the feature workflow's
verification step (out of scope by design; integration path documented only).

# Commands

- `bundle exec rspec spec/owl/specs/internal/trace_checker_spec.rb spec/owl/specs/trace_spec.rb spec/owl/cli/spec_trace_command_spec.rb`
  => 19 examples, 0 failures.
- `bundle exec rspec` (full suite) => 1372 examples, 0 failures, 1 pending.
- `bundle exec rubocop <8 changed lib + spec files>` => no offenses.
- Smoke: `owl spec validate demo` => valid:true on the seeded template;
  `owl spec trace demo --json` => coverage report; `owl spec trace demo --strict`
  => exit 1 when untraced/dangling.

# Outcomes

- Status: passed.
- `lib/owl/specs/api.rb` line coverage: 100% (not listed under "Public API files
  below 100% line coverage"; only the pre-existing `lib/owl/steps/api.rb` 99.16%
  gap remains, unrelated to P5).
- Full-suite exit code 1 originates solely from the pre-existing steps/api.rb
  coverage gate; 0 test failures.
- Test classifications proven: fully-traced => valid; scenario without TEST =>
  untraced + `--strict` ok:false; path-like missing ref => dangling; prose ref
  => unverified (still valid); multiple TEST lines; zero requirements => vacuous
  valid; read-only (disk unchanged); bullet/bold/indent tolerance; fenced
  `#### Scenario` not miscounted; deterministic order.
- README.md was NOT dirtied by the suite (no restore needed). Throwaway smoke
  spec under `/tmp/owltrace` removed; no `specs/<domain>` left in the repo.
