---
type: verification
status: passed
summary: >-
  WHEN/THEN scenario validation is now case-insensitive and the missing-clause
  error is actionable; full rspec suite (1797 examples, 0 failures) and rubocop
  on changed files are green.
---

# Verification report

## Summary

TASK-0022 (hotfix) loosens the `require_when_then` scenario validation contract.
`Owl::Validation::Internal::WhenThenChecker` previously matched only UPPERCASE
`WHEN`/`THEN`, rejecting well-formed Title-case (`- When …`) or lower-case
(`- when …`) Gherkin bullets. Both clause regexes in `CLAUSE_RES` now carry the
`i` flag, and the `scenario_missing_clause` violation `description` spells out
the expected line format. `type` and `missing` fields are unchanged so
downstream consumers are unaffected. Version bumped 0.8.1 → 0.9.0 (MINOR) with a
matching CHANGELOG entry.

## Commands

- `bundle exec rspec spec/owl/validation/internal/when_then_checker_spec.rb spec/owl/validation/brief_grammar_spec.rb spec/owl/validation/api_spec.rb` — targeted, 37 examples, 0 failures.
- `bundle exec rspec` — full suite; `git checkout README.md` after (known test-isolation wart).
- `bundle exec rubocop lib/owl/validation/internal/when_then_checker.rb spec/owl/validation/internal/when_then_checker_spec.rb lib/owl/version.rb`.

## Outcomes

- Targeted specs: **37 examples, 0 failures**.
- Full suite: **1797 examples, 0 failures, 1 pending** (pre-existing pending),
  exit 0. README needed no checkout this run (`Updated 0 paths`).
- Rubocop: **3 files inspected, no offenses detected** (only the pre-existing
  plugin-migration informational notices).
- New spec cases added and passing: Title-case `- When/- Then` validates,
  lower-case validates, UPPERCASE back-compat still validates, and the
  missing-clause message contains the expected-format hint. The one assertion
  pinned to the old message string was updated.

## Not run

- No manual CLI / e2e runs beyond the automated suite — the change is a pure
  internal-checker regex/message tweak fully exercised by unit + integration
  specs (`brief_grammar_spec`, `validation/api_spec`).

## Failures or blockers

- None.

## Residual risks

- Low. The change only *broadens* what validates (case-insensitivity) and
  enriches an error string; it cannot newly reject previously-passing input.
- Any external tooling string-matching the old `is missing a WHEN clause.`
  wording would break, but a repo-wide grep for `is missing a` /
  `scenario_missing_clause` found no other coupling (`brief_grammar_spec` keys on
  `missing`, `validation/api_spec` keys on `type`).
