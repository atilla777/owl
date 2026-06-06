---
status: draft
summary: Ordered checklist to add the specs storage role, the spec artifact type, Owl::Specs::Api, and the owl spec list/show/path/validate CLI, with backward-compatible config defaulting and full specs.
---

# Goal

Ship the persistent project-level `spec` artifact (storage role + type + access CLI) without
breaking existing configs, with 100% coverage on `specs/api.rb` and green gates.

# Checklist

1. **Storage role `specs`** — add `'specs'` to `Storage::Api::STANDARD_ROLES`
   (`lib/owl/storage/api.rb`). Add `specs: "{{project.root}}/specs"` to the default config
   template (`lib/owl/config/internal/default_template.rb`). Find where the active profile's
   roles are assembled/validated and inject a default `specs` path when the loaded config omits
   it (so `STANDARD_ROLES` validation passes for legacy configs). Keep the injection at the
   resolution layer — do NOT rewrite user files.

2. **Backward-compat regression** — spec proving a config WITHOUT
   `settings.storage.roles.specs` still passes `config validate` and that
   `Storage::Api.resolve(role:'specs', ...)` yields `<root>/specs`.

3. **`spec` artifact type** — scaffold `.owl/artifacts/spec/artifact.yaml` (+
   `templates/default.md`) via `owl artifact-type new spec` then edit (or write the YAML through
   the artifact-type tooling — do not hand-edit outside the CLI contract where avoidable):
   - front_matter: required `status` (enum `draft|active`), `summary`.
   - validation.required_sections: `Purpose`, `Requirements`.
   - validation: `require_scenarios: true`, `require_when_then: true`, `forbid_placeholders: true`
     (NOT `forbid_empty_sections`).
   - template seeds `## Purpose`, `## Requirements`, one `### Requirement` + `#### Scenario`
     (WHEN/THEN) that VALIDATES clean against the above keys.
   - Confirm `owl artifact-type validate spec` passes.

4. **SpecLocator internal** — `lib/owl/specs/internal/spec_locator.rb` (`module_function`):
   `validate_domain(domain)` (`/\A[a-z0-9][a-z0-9_-]*\z/`), `path(root:, domain:)`,
   `dir(root:)`, `list(root:)`, `read(root:, domain:)`. All FS via `Owl::Storage::Api`
   (resolve/children/read/exists?).

5. **`Owl::Specs::Api`** — `lib/owl/specs/api.rb` (public, 100% coverage):
   `path/list/show/validate(root:, domain:?)` delegating to SpecLocator; `validate` builds a
   descriptor from `Artifacts::Api.find(root:, key:'spec')` (path = resolved spec path,
   validation + front_matter from the type) and calls
   `Validation::Internal::ArtifactRunner.validate(descriptor)`; return `{valid, violations}`.
   Structured errors `invalid_domain`, `spec_not_found` (+`available`).

6. **CLI command modules** — `lib/owl/cli/internal/commands/spec_{list,show,path,validate}.rb`
   mirroring P6's archive commands (`JsonPrinter`, `TaskSupport`, `--root/--json`; `show`
   non-JSON prints raw body). Required positionals → `invalid_arguments`.

7. **Dispatcher** — in `lib/owl/cli/api.rb`: `require_relative` the four commands; add
   `when 'spec' then dispatch_spec(args, **kwargs)` with `list|show|path|validate` routing;
   update `HELP_TEXT`.

8. **Dogfood config** — `bin/owl config set settings.storage.roles.specs '{{project.root}}/specs'`
   for THIS repo (or confirm the default injection covers it); verify `owl config show` lists
   the `specs` role.

9. **Archive isolation spec** — test that archiving a task leaves an existing
   `specs/<domain>/spec.md` untouched.

10. **Specs** — `spec/owl/specs/api_spec.rb` (path/list/show/validate happy + empty + missing +
    invalid_domain + a validate that surfaces `requirement_without_scenario`),
    `spec/owl/specs/internal/spec_locator_spec.rb`, and CLI dispatch specs under `spec/owl/cli/`
    (routes + non-JSON body + invalid args). Confirm `specs/api.rb` 100% via simplecov.

11. **Gates** — `bundle exec rspec` green for touched areas (and confirm no NEW file drops below
    100% among `lib/owl/**/api.rb`); `bundle exec rubocop` clean on changed files (never `-A`).

# Smoke test

```
bundle exec owl config show --json                  # specs role present
bundle exec owl spec path ui --json                 # -> <root>/specs/ui/spec.md
bundle exec owl spec list --json                    # -> {ok:true, specs:[]} initially
mkdir -p specs/ui && cp .owl/artifacts/spec/templates/default.md specs/ui/spec.md
bundle exec owl spec list --json                    # -> specs:[{domain:"ui",...}]
bundle exec owl spec show ui --json                 # -> body
bundle exec owl spec validate ui --json             # -> {valid:true} for the seeded template
# break it: remove the Scenario under a Requirement -> validate reports requirement_without_scenario
bundle exec owl spec show nope --json               # -> spec_not_found + available
bundle exec owl spec path '../x' --json             # -> invalid_domain
bundle exec rspec spec/owl/specs spec/owl/cli spec/owl/config
bundle exec rubocop lib/owl/specs lib/owl/cli/api.rb lib/owl/cli/internal/commands/spec_*.rb lib/owl/storage/api.rb lib/owl/config
```
(Clean up the throwaway `specs/ui` after smoke unless it should seed a real domain.)
