---
status: resolved
summary: P1 project-level `spec` artifact reviewed adversarially — backward-compat, path-traversal, FS-access, artifact-type validation, CLI dispatch, and coverage all verified clean; no blockers/majors, two nits, full gates green (1297 examples 0 failures, specs/api.rb 100%).
---

# Summary

Adversarial self-review of TASK-0002 (P1: project-level, domain-addressed,
persistent `spec` artifact). Scope reviewed: `lib/owl/specs/**`, the `specs`
storage role + `ROLE_DEFAULTS`, config backend backward-compat injection,
`spec` artifact type + template, `owl spec list|show|path|validate` CLI,
`help_text.rb` extraction, and the supporting specs. Task/archived artifacts
were ignored per instruction.

Verdict: clean. Every central risk called out in the brief/design is correctly
handled and independently verified by running the code, not by trusting the
verification report. No blockers, no majors. Two nits, neither a defect.

# Findings

## Backward compatibility (central risk) — verified clean
- Injection lives in `Config::Backends::Filesystem#inject_role_defaults`, called
  from `build_document`, which is the single load path feeding BOTH validation
  (`Validator` reads `document.storage`, the injected copy) AND resolution
  (`active_profile` → `Storage::Api.resolve` reads the injected profile roles).
  So the default is applied for both paths.
- Operates on a `deep_dup`, so the on-disk config is never rewritten —
  proven by `specs_role_backward_compat_spec.rb` ("does not rewrite the on-disk
  config").
- Clobber-safety: `roles[role] ||= { 'path' => path }` only fills when absent, so
  a user-set `specs` path is preserved. Correct by construction.
- Runtime-verified on a legacy config (specs role stripped from a freshly
  inited project): `config validate` → valid, `Storage::Api.resolve(specs)` →
  `<root>/specs`, and `config show` `storage.roles_present` includes `specs`
  (derived from the injected document, so no cosmetic gap either).
- Non-Hash `storage`/`roles`/`profile` shapes are guarded (`is_a?(Hash)`).

## Path traversal — verified clean
- `SpecLocator.validate_domain` runs the slug regex `/\A[a-z0-9][a-z0-9_-]*\z/`
  BEFORE any resolve, in `path`, which `read`/`show`/`validate` all funnel
  through; `list` enumerates real children only. Consistent across all four
  surfaces.
- Defeat attempts runtime-tested and all rejected with `invalid_domain`:
  `../x`, leading dash `-bad`, empty string `''`. Slashes and `..` cannot reach
  a resolve.

## FS-access rule (docs/agents/27 / no_direct_fs) — verified clean
- `grep -rE 'File\.|Dir\.|Pathname|IO\.|FileUtils' lib/owl/specs/` matches only a
  doc comment; zero direct FS calls. All I/O via `Owl::Storage::Api`
  (resolve/children/read/exists?). The meta-spec gate passes.

## `spec` artifact type — verified clean
- `bin/owl artifact-type validate spec` → `valid:true`.
- `forbid_empty_sections` is correctly NOT enabled (confirmed by grep);
  `require_scenarios`/`require_when_then`/`forbid_placeholders` are.
- Seeded template validates clean (`owl spec validate` on a copy → `valid:true`,
  no violations), and is regression-covered by `specs/api_spec.rb` reading the
  actual on-disk template body.
- Breaking it fires the expected blocker: removing a `#### Scenario` →
  `requirement_without_scenario` at `level:error`, `valid:false`. Also
  cross-checked `missing_section` (drop `## Purpose`) and `placeholder_text`
  (`TODO`) both surface at `level:error` → `valid:false`.

## `validate` descriptor wiring — verified clean
- `Specs::Api.validate` builds the descriptor (`key/path/exists/validation/
  front_matter`) from `Artifacts::Api.find('spec')` and reuses
  `ArtifactRunner.validate`; `valid` derived via `blocking_count` (level==error).
- Missing spec → `read` returns `spec_not_found` early (no crash); covered by a
  test and runtime-confirmed.

## CLI dispatch — verified clean
- `dispatch_spec` routes `list|show|path|validate`; unknown subcommand →
  `unknown_command`. `show --no-json` prints raw body. Missing positional →
  `invalid_arguments` (show/path/validate). New top-level `spec` collides with
  nothing (added to the `case`, refactor moved init/publish/instructions/status
  into `SIMPLE_COMMANDS` — behaviour preserved, suite green). `HELP_TEXT`
  extracted to `cli/internal/help_text.rb` and lists `spec`.

## Coverage — verified from simplecov
- Full `bundle exec rspec`: 1297 examples, 0 failures, 1 pending (pre-existing
  storage concurrent-write pending). `lib/owl/specs/api.rb` is NOT in the
  below-100% list → 100%. The only sub-100% public API file is the documented,
  unrelated `lib/owl/steps/api.rb` (99.16%).

## Nit 1 (nit) — `spec list` uses `parser.parse!` while show/path/validate use
`parser.parse`. Cosmetic inconsistency; `list` has no positional so behaviour is
identical. Resolution: left as-is, not a defect.

## Nit 2 (nit) — No explicit test asserts the `||=` injection preserves a
user-set `specs` path (only the no-rewrite + default-injection cases are
tested). The guard is trivially correct and the no-rewrite test exercises the
same code path. Resolution: noted as a low-value follow-up; not blocking.

# Resolution

- Backward-compat (validate + resolve + no-clobber + no-rewrite): verified,
  no action — resolution: confirmed correct, runtime + spec evidence.
- Path traversal: verified, no action — resolution: all attack inputs rejected.
- FS-access gate: verified, no action — resolution: zero direct FS calls.
- Artifact type + seeded template + broken-spec violation: verified, no action —
  resolution: validates clean, `requirement_without_scenario` fires as a blocker.
- Descriptor wiring + missing-file handling: verified, no action.
- CLI dispatch + help text + coverage: verified, no action.
- Nit 1 (parse! vs parse): resolution: accepted as-is (no behavioural impact).
- Nit 2 (no clobber-preservation test): resolution: recorded as an optional
  follow-up; code is correct by construction.

No code changes were required — the implementation withstood the adversarial
pass. `status: resolved` (no open blocker/major).
