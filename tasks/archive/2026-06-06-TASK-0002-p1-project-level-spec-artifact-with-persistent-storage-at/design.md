---
status: approved
summary: Add `specs` to STANDARD_ROLES with a defaulted path (backward-compatible), register a `spec` artifact type enabling require_scenarios/require_when_then/forbid_placeholders (NOT forbid_empty_sections), and ship Owl::Specs::Api + owl spec list/show/path/validate, domain-addressed via PathTemplate, reusing the validation runner.
---

# Context

`Storage::Api::STANDARD_ROLES = %w[control local_state index tasks archive docs]` is the
required role set; the config validator (`config/internal/validator.rb`) requires each present
in the active profile but tolerates extra roles. `Storage::Api.resolve(role:, profile:, root:,
vars:)` renders a role's path template, and `PathTemplate` supports arbitrary dotted
placeholders (e.g. `{{domain}}`) — so `specs/{{domain}}/spec.md` resolves directly given
`vars: {domain: 'ui'}`. Artifact-type definitions (validation + front_matter + template) load
via `Owl::Artifacts::Api.find(root:, key:)`. The validation runner
(`Validation::Internal::ArtifactRunner.validate(descriptor)`) already accepts a descriptor
`{path, validation, front_matter, exists}` and now (post-P3) runs the semantic checkers. P6
established the pattern for a read-only storage surface (reader + Api + dispatched CLI).

# Decision

**1. `specs` becomes a first-class, defaulted storage role.**
- Add `'specs'` to `STANDARD_ROLES`.
- Add `specs: "{{project.root}}/specs"` to the default config template
  (`config/internal/default_template.rb`) so `owl init` scaffolds it.
- **Backward-compat:** where the active profile's roles are assembled, inject a default
  `specs` path (`{{project.root}}/specs`) when the loaded config omits it, so existing
  `.owl/config.yaml` files keep validating and resolving. (Implement at the profile-resolution
  layer that feeds `STANDARD_ROLES` validation, not by mutating user files.) Add a regression
  test with a config lacking `specs`.
- This repo's own `.owl/config.yaml` gets `specs` added via `owl config set`
  (`settings.storage.roles.specs`) so the dogfood project is explicit.

**2. `spec` artifact type** at `.owl/artifacts/spec/artifact.yaml` (+ `templates/default.md`):
- `front_matter`: `status` enum `[draft, active]`, `summary` (required).
- `required_sections`: `Purpose`, `Requirements`.
- Semantic validation keys (from P3): `require_scenarios: true`, `require_when_then: true`,
  `forbid_placeholders: true`. **NOT** `forbid_empty_sections` — per the TASK-0001 review note,
  enabling it together with `require_scenarios` would force prose under every `### Requirement`;
  a spec legitimately may have a Requirement whose body is only its `#### Scenario`(s). Omitting
  it keeps the format permissive where it should be while still enforcing scenario presence and
  WHEN/THEN.
- Template seeds `## Purpose`, `## Requirements`, and one example `### Requirement` +
  `#### Scenario` (WHEN/THEN) so a fresh spec validates and shows the grammar.

**3. `Owl::Specs::Api`** (`lib/owl/specs/api.rb`, public → 100% coverage) + internal
`lib/owl/specs/internal/spec_locator.rb` (`module_function`):
- `path(root:, domain:)` → validate domain slug (`/\A[a-z0-9][a-z0-9_-]*\z/`, else
  `invalid_domain`), resolve via `Storage::Api.resolve(role: 'specs', vars: {domain:})`; return
  `{domain, path}`.
- `list(root:)` → `Storage::Api.children` of the specs role dir; each subdir containing
  `spec.md` → `{domain, path}`; empty/absent dir → `[]`.
- `show(root:, domain:)` → read body; `spec_not_found` (with `available` domains) when absent.
- `validate(root:, domain:)` → build a descriptor from the `spec` artifact type
  (`Artifacts::Api.find`) with the resolved path, hand it to `ArtifactRunner.validate`, return
  `{valid, violations}` shaped like `owl artifact validate`.
- `resolve(role:)` for specs goes through storage; no `File`/`Dir` in Api/internal (FS-access
  rule, `docs/agents/27`).

**4. CLI** — `dispatch_spec` in `cli/api.rb` (new top-level `spec` command) with
`list|show|path|validate`, mirroring P6's `dispatch_archive`. Command modules `spec_list.rb`,
`spec_show.rb`, `spec_path.rb`, `spec_validate.rb` under `cli/internal/commands/`, using
`JsonPrinter`/`TaskSupport`, `--root/--json`; `show` non-JSON prints the raw body. Update
`HELP_TEXT`.

**5. Archive isolation** — no change needed: `owl archive` only moves `tasks/<ID>/`. Add a test
asserting that archiving a task leaves a `specs/<domain>/spec.md` in place.

# Alternatives

- **Store specs under the `docs` role** (`docs/specs/<domain>/spec.md`) — rejected: the user
  chose a top-level `specs/` catalog; a dedicated role keeps the formal contract separate from
  narrative docs (the whole point of Problem 1).
- **Keep `spec` task-scoped and publish to `specs/`** — rejected: that reintroduces archival
  coupling and the free-form publish path Problem 1/P4 exist to remove.
- **Make `specs` a non-standard (optional) role** — rejected: a first-class role with a default
  is cleaner, makes `owl init` scaffold it, and the defaulting keeps backward-compat anyway.
- **Enable `forbid_empty_sections` on `spec`** — rejected (see Decision §2): strict composition
  with `require_scenarios`.
- **Validate specs by faking a task** — rejected: domain-addressed validation via a dedicated
  descriptor builder is cleaner than coercing the task-scoped resolver.

# Risks

- **STANDARD_ROLES change breaking existing configs** — mitigated by the profile-level default
  injection + a regression test with a `specs`-less config; this is the central risk and is
  explicitly tested.
- **Path traversal via domain** — mitigated by strict slug validation before any resolve.
- **Coupling P1 to P2/P4** — kept minimal: P1 ships storage + type + read/validate only. Writing
  and delta-merge are out of scope; the template provides a valid starting body so specs can be
  hand-edited meanwhile.
- **Config-schema drift** — if a JSON schema enumerates roles, update it; otherwise none.

# API

New public: `Owl::Specs::Api.{path,list,show,validate}(root:, domain:?)` → `Result`.
New internal: `Owl::Specs::Internal::SpecLocator`.
New storage role: `specs` → `{{project.root}}/specs` (added to `STANDARD_ROLES` + default
template + profile default).
New artifact type: `spec` (markdown).
New CLI: `owl spec list|show <domain>|path <domain>|validate <domain>` (additive top-level
command). JSON shapes: `list -> {ok, specs:[{domain,path}]}`; `show -> {ok, domain, path, body}`;
`path -> {ok, domain, path}`; `validate -> {ok, valid, violations[]}`. Errors: `invalid_domain`,
`spec_not_found` (+`available`). `lib/owl/specs/api.rb` requires 100% line coverage.
