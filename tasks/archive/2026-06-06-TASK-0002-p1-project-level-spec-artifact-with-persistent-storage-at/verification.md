---
status: passed
summary: All gates green — full rspec 1297 examples 0 failures, specs/api.rb at 100% line coverage, rubocop clean on changed files, and the backward-compat + archive-isolation regressions pass.
---

# Verification report

## Summary

Implemented Problem 1 (P1): a project-level, domain-addressed, persistent `spec`
artifact at `specs/<domain>/spec.md` with a first-class `specs` storage role,
a `spec` artifact type, `Owl::Specs::Api` (read/resolve/validate), and an
`owl spec list|show|path|validate` CLI. Storage-only scope — writing/merging
spec content is out of scope.

All acceptance gates pass:

- Full `bundle exec rspec`: 1297 examples, 0 failures, 1 pending.
- New domain `lib/owl/specs/api.rb` at 100.00% line coverage (26/26); internal
  `spec_locator.rb` also 100.00% (52/52).
- The only public API file below 100% is the documented pre-existing gap
  `lib/owl/steps/api.rb` (99.16%), unrelated to this task.
- `bundle exec rubocop` clean on all 21 changed files.
- Backward-compat: a config without a `specs` role still validates and resolves
  `specs` to `<root>/specs` (regression test passes).
- Archive isolation: archiving a task leaves `specs/<domain>/spec.md` untouched
  (regression test passes).

## Commands

```
# Spec artifact type validates
bin/owl artifact-type validate spec --json          # => valid: true

# CLI smoke (dogfood repo)
bin/owl config show                                  # roles_present includes "specs"
bin/owl spec path ui --json                          # => <root>/specs/ui/spec.md
bin/owl spec list --json                             # => {ok:true, specs:[]}
bin/owl spec show nope --json                        # => spec_not_found (+available)
bin/owl spec path '../x' --json                      # => invalid_domain
bin/owl --help | grep '  spec '                      # spec command listed

# Backward-compat (legacy config without specs role)
bin/owl config validate                              # => valid: true (specs injected)

# Full gates
bundle exec rspec                                    # 1297 examples, 0 failures, 1 pending
bundle exec rubocop <21 changed files>               # no offenses detected
```

Targeted suites:

```
bundle exec rspec spec/owl/specs spec/owl/cli/spec_command_spec.rb \
  spec/owl/config/specs_role_backward_compat_spec.rb               # 33 examples, 0 failures
```

## Outcomes

- `specs` storage role added to `Storage::Api::STANDARD_ROLES` with a
  `ROLE_DEFAULTS` default; config backend injects the default at
  profile-resolution time without rewriting user files (legacy configs keep
  validating). Default config template + this repo's `.owl/config.yaml` carry
  the role explicitly.
- `spec` artifact type registered (`.owl/artifacts/spec/` + repo-root seed
  `artifacts/spec/` + registry render): front_matter `status` enum
  `[draft, active]` + `summary`; required sections `Purpose`, `Requirements`;
  semantic keys `require_scenarios`, `require_when_then`, `forbid_placeholders`
  (NOT `forbid_empty_sections`). The seeded template validates clean and a
  `### Requirement` lacking a `#### Scenario` reports
  `requirement_without_scenario`.
- `Owl::Specs::Api.{path,list,show,validate}` + `Internal::SpecLocator` with
  slug validation (`/\A[a-z0-9][a-z0-9_-]*\z/`) before any resolve; all FS
  access via `Owl::Storage::Api`. Structured errors `invalid_domain`,
  `spec_not_found` (+`available`).
- CLI: `dispatch_spec` in `cli/api.rb` routing `list|show|path|validate`;
  command modules mirror the archive commands; `show --no-json` prints the raw
  body; HELP_TEXT updated (extracted to `cli/internal/help_text.rb` to keep the
  Api module within its length budget).
- Existing artifact-count assertions updated from six to seven seeded artifact
  types; the template-skeleton suite excludes the project-level `spec` type
  (not task/workflow-scoped).

Status: passed.
