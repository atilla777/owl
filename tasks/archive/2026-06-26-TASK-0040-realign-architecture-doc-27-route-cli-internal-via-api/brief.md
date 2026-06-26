---
status: approved
summary: Realign architecture doc 27 with the real backend pattern, route cli->Internal via Api facades, split the workflows backend god-object, and dedup the artifacts/workflows loaders.
---

# Brief

## Problem

The codebase is better-engineered than its docs admit, but the gap is now a
maintainability risk:
- `docs/agents/27_Owl_Ruby_code_architecture.md` describes a 3-tier model where
  all FS I/O funnels through `Storage::Api`. Reality is an undocumented
  per-domain backend pattern (`backend.rb` + `backends/filesystem.rb` + `internal/`),
  with ~80 cross-domain `Internal::*` calls — including `cli -> *::Internal`,
  which contradicts "CLI is a thin adapter that only calls `Owl::<Domain>::Api`".
- `lib/owl/workflows/backends/filesystem.rb` is an 803-line god object (44 methods,
  `rubocop:disable Metrics/ClassLength`) holding gate logic inline, in contrast to
  the clean delegating `tasks/backends/filesystem.rb`.
- Three error conventions coexist: `Owl::Result`, typed exceptions, and positional
  tuples `[:ok, value]` in loaders.
- `artifacts/` and `workflows/` carry near-duplicate `cache.rb` / `registry_loader.rb`
  / `source_loader.rb`.

## Goal

Doc 27 reflects the actual backend architecture; the CLI no longer reaches into
domain `Internal::*`; the workflows backend is decomposed like `tasks`; loader
duplication is collapsed. No behavior change (pure refactor) — tests stay green.

## Scenarios

### Requirement: Doc reflects reality
The architecture doc SHALL describe the per-domain backend pattern and the
Layer-A/B/C bootstrap exceptions actually present in the code.

#### Scenario: New contributor reads doc 27
- WHEN a contributor reads doc 27 and inspects `lib/owl/<domain>/`
- THEN the documented model matches what they find (backend + backends/filesystem + internal)

### Requirement: CLI calls only Api facades
The `cli/` layer SHALL invoke domain logic only through `Owl::<Domain>::Api`,
not `Owl::<Domain>::Internal::*`.

#### Scenario: Audit cli internal-reaches
- WHEN the cli command files are grepped for `::Internal::`
- THEN no domain-Internal reach remains (or each is justified and documented)

### Requirement: No regression
The refactor SHALL be behavior-preserving.

#### Scenario: Full suite after refactor
- WHEN `bundle exec rspec` runs
- THEN 0 failures and api.rb coverage stays at 100%

## Edge cases

- Some `cli -> Internal` reaches may need new `Api` methods — those are additive,
  back-compat (no JSON contract change).
- Splitting the workflows backend must keep the public Backend method signatures stable.
- Loader dedup must preserve each domain's distinct field mappings.

## Acceptance criteria

- Doc 27 rewritten around the backend model; stale "all FS via Storage" claim removed.
- `grep -rn '::Internal::' lib/owl/cli/` → 0 (or documented exceptions only).
- `workflows/backends/filesystem.rb` decomposed; no single file > ~300 lines without justification.
- Shared loader/cache helper extracted; duplicate trio removed.
- Suite green, api.rb coverage 100%, RuboCop clean. Version bump as appropriate + CHANGELOG.
