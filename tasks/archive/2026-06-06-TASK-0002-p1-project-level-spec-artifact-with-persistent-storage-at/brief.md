---
status: approved
summary: Introduce a project-level, domain-addressed `spec` artifact persisted at specs/<domain>/spec.md (never archived), with a `specs` storage role and an owl spec list/show/path/validate CLI, as the persistent source of truth for verifiable behaviour.
---

# Problem

Owl has no persistent, project-level source of truth for *verifiable behaviour*. Task
artifacts (`brief`, `design`, `plan`, `review`, `verification`) live under `tasks/<TASK-ID>/`
and are **archived** with the task, so the contract a change was made against disappears from
the live tree. Narrative docs under `docs/` are prose, not a machine-checkable contract.

The Owl-vs-OpenSpec comparison (Problem 1) calls for a "living spec": a persistent set of
Requirements/Scenarios that survives task archival and against which future changes are made —
OpenSpec's `openspec/specs/<domain>/spec.md`. Owl currently cannot express or store this.

# Goal

Add a `spec` artifact that is **project-level and persistent** (not task-scoped, never
archived), addressed by **domain**, stored at `specs/<domain>/spec.md` (the location chosen by
the user). Provide a minimal read/resolve/validate CLI so agents and humans can work with specs
through `bin/owl` (never by reading files directly). Writing/merging spec content is delivered
later by P4 (delta-merge); P2 standardises the Requirement/Scenario grammar. This task ships the
**storage + artifact type + access surface**.

Scope:

- A first-class `specs` storage role at `{{project.root}}/specs`, backward-compatible so
  existing `.owl/config.yaml` files (which lack it) keep validating.
- A `spec` artifact type (markdown) whose validation reuses the P3 semantic keys so a spec is a
  formal Requirement/Scenario document from day one.
- `owl spec list | show <domain> | path <domain> | validate <domain>` (JSON-first).
- Specs are excluded from `owl archive` (they live outside `tasks/`).

# Scenarios

### Requirement: Specs persist at a project-level domain-addressed location

The system SHALL store each spec at `specs/<domain>/spec.md` under a dedicated persistent
storage role, independent of any task.

#### Scenario: Resolve a spec path by domain
- WHEN the user runs `owl spec path ui --json`
- THEN the output resolves to `<project.root>/specs/ui/spec.md` via the `specs` storage role
- AND the path is stable regardless of any current task or archival state

#### Scenario: Spec survives task archival
- WHEN a task that created/updated a spec is archived with `owl archive`
- THEN the file under `specs/<domain>/spec.md` is NOT moved into `tasks/archive/`
- AND `owl spec show <domain>` still returns its body

### Requirement: List existing specs

The CLI SHALL enumerate every domain that has a spec.

#### Scenario: List populated and empty
- WHEN the user runs `owl spec list --json`
- THEN the output is `{ok:true, specs:[{domain, path}, ...]}` (empty list, not an error, when none exist)

### Requirement: Read a spec body

The CLI SHALL return the raw body of a spec by domain.

#### Scenario: Show existing / missing
- WHEN the user runs `owl spec show <domain> --json`
- THEN an existing spec returns `{ok:true, domain, path, body}`
- AND a missing domain returns a structured `spec_not_found` error with available domains

### Requirement: Validate a spec against the formal format

The CLI SHALL validate a spec file against the `spec` artifact type's rules, reusing the
existing validation runner (P3 semantic checks included).

#### Scenario: Validate a spec
- WHEN the user runs `owl spec validate <domain> --json`
- THEN the output is `{ok, valid, violations[]}` exactly like `owl artifact validate`
- AND a spec with a `### Requirement` lacking a `#### Scenario` reports a blocking
  `requirement_without_scenario` violation

### Requirement: Backward compatibility for existing projects

The system SHALL NOT break existing Owl projects whose config predates the `specs` role.

#### Scenario: Config without specs role
- WHEN an existing `.owl/config.yaml` has no `settings.storage.roles.specs`
- THEN config validation still passes and the `specs` role resolves to its default
  `{{project.root}}/specs`

# Edge cases

- Domain naming: restrict to a safe slug (`[a-z0-9][a-z0-9_-]*`) to avoid path traversal;
  reject `..`/slashes in the domain arg.
- Empty `specs/` directory or absent role dir → `list` returns `[]`, not an error.
- `validate` on a non-existent spec → structured `spec_not_found`, not a validation crash.
- The `spec` artifact type enabling both `forbid_empty_sections` and `require_scenarios` would
  force prose under every Requirement (P3 strict-composition note from TASK-0001 review) — decide
  at design which semantic keys to enable so a Requirement→Scenario with no intervening prose is
  still valid.
- `owl archive` must remain unaffected; adding the `specs` role must not change archive scope.

# Acceptance criteria

- [ ] `specs` storage role added (first-class, defaulted) without breaking existing configs;
      config validation green for configs with and without an explicit `specs` role.
- [ ] `spec` artifact type registered with template + validation (formal Requirement/Scenario
      sections; semantic keys chosen per design).
- [ ] `owl spec list | show <domain> | path <domain> | validate <domain>` implemented, JSON-first,
      with structured errors (`spec_not_found`, invalid-domain).
- [ ] Domain inputs are slug-validated; no path traversal possible.
- [ ] `owl archive` leaves `specs/` untouched (covered by a test).
- [ ] New read/resolve/validate logic lives in `Owl::Specs::Api` (public file → 100% line
      coverage) going through storage roles, never hard-coded paths.
- [ ] RSpec coverage for list/show/path/validate (incl. empty, missing, invalid-domain) and the
      backward-compatible role default.
- [ ] `bundle exec rspec` green for touched areas; `bundle exec rubocop` clean on changed files
      (never `-A`).
