---
status: shipped
summary: Behavior-preserving refactor across 4 workstreams — realign doc 27, route cli→Internal via Api facades, decompose the workflows backend god-object like tasks, and collapse loader duplication into the existing Owl::Internal namespace. Shipped as 4 sequential green commits.
---

# Design

## Context

Four independent maintainability gaps in an otherwise well-engineered codebase
(see brief). All changes are behavior-preserving; the guard rail is `bundle exec
rspec` (1984 examples, currently 0 failures) plus 100% line coverage on every
`lib/owl/**/api.rb`. Per user decision, the task ships as **4 sequential commits**,
each leaving the suite green, in the order: doc 27 → loader dedup → cli→Api →
workflows-backend split (cheapest/safest first, riskiest last).

## Decision

### WS1 — Doc 27 realignment (docs only, commit 1)
Rewrite `docs/agents/27_Owl_Ruby_code_architecture.md` (Russian) to describe the
**actual** per-domain backend pattern: each domain `lib/owl/<d>/` exposes
`api.rb` (public facade) → `backend.rb` (interface) → `backends/filesystem.rb`
(impl) → `internal/*` (service objects), with `local.rb` for runtime-state paths.
Remove the stale "все FS I/O только через `Owl::Storage::Api`" claim (Storage is
one domain among many, not a universal funnel). Document the three legitimate
bootstrap exceptions actually in the code (the Layer-A/B/C `Owl::Internal::*`
cross-cutting helpers: `BackendResolver`, `Cache`, `Paths`, `SeededLoader`,
`GemAssets`) and the rule that `cli/` calls only `<Domain>::Api`.

### WS2 — Loader dedup (commit 2)
`Owl::Internal` already hosts cross-cutting helpers (`Cache`, `Paths`,
`SeededLoader`). Collapse the near-identical domain loader pairs into it,
parameterized by a small per-domain config (key prefix, field mapping):
- `cache.rb` (4 diff lines), `source_loader.rb` (8), `seeded_sources.rb` (6):
  near-identical — domain copies become thin delegators to a shared
  `Owl::Internal::*` helper (or are deleted in favour of the existing one).
- `registry_loader.rb` (29 diff lines): shared skeleton + **domain-specific field
  mapping passed in** (preserves each domain's distinct fields — brief edge case).
- `default_template.rb` (128 diff lines): genuinely divergent (artifact vs workflow
  template bodies) → **leave separate**, do not force a shared abstraction.

### WS3 — cli → Api facades (commit 3)
~24 cross-domain `<Domain>::Internal::*` reaches from `lib/owl/cli/`. Replace each
with a call to the owning domain's `Api`, adding **additive** Api methods where one
does not yet exist (back-compat, no JSON-contract change). Breakdown:
- `Steps::Internal::ActiveStepLock` (~13 reaches) — the dominant one. Add
  `Steps::Api` facade(s) for acquire/release/with-lock so cli never touches the
  lock class directly.
- `Steps::Internal::DriftDetector` / `DriftPolicy` (~4), `Subagents::Internal::
  OutputSpec` / `ReportPaths` (~5), `Tasks::Internal::TaskReader` / `Paths` (2),
  `Workflows::Internal::StepContextFrontmatterCheck` (1) — add matching `Api`
  methods.
- `Cli::Internal::UserFileReader` is cli's **own** internal — leave as-is (not a
  cross-domain reach).
Every new `api.rb` line needs spec coverage to keep api.rb at 100%.

### WS4 — workflows backend split (commit 4, riskiest)
`lib/owl/workflows/backends/filesystem.rb` (803 lines, 44 methods) mirrors the
clean `tasks` backend: a thin delegator over many `internal/*` service objects.
Extract the inline private logic into new/existing `workflows/internal/*` objects,
keeping the **public Backend method signatures byte-stable**:
- ready-steps gating (`apply_conditional_gate`, `conditional_predicate`,
  `apply_plan_approval_gate`, `apply_children_gate`, `children_ready?`,
  `definition_steps_for`) → fold into the existing `ready_resolver.rb`.
- scaffold (`scaffold`, `resolve_scaffold_body`, `safe_parse`,
  `detect_duplicate_variant_keys`, `mapping_value`, `find_duplicate_scalar_key`)
  → new `internal/scaffolder.rb`.
- validate (`validate`, `load_for_validate`, `load_from_path`,
  `load_from_registry`) → new `internal/validation_loader.rb`.
- context (`context_show/set`, `resolve_context_target`, `context_file_for`,
  `read_step_context[_frontmatter]`) → extend `internal/step_context_resolver.rb`.
- registry writes (`register`, `unregister`, `guard_project_owned`,
  `load_registry_raw`, `workflow_source_path`) → new `internal/registry_writer.rb`.
- error builders → `internal/errors.rb` (or keep inline if trivial).
Target: no single file > ~300 lines without justification.

## Alternatives

- **WS2 — force-dedup `default_template` too.** Rejected: the two bodies diverge by
  128 lines (different template semantics); a shared abstraction would be a leaky
  parameter-bag. Leaving them separate is the honest call (brief edge case).
- **WS3 — relocate `ActiveStepLock` into cli instead of fronting it with Api.**
  Rejected: the lock is step-domain state; cli is an adapter. Api facade keeps the
  layering the doc now promises.
- **WS4 — one mega-commit for the whole task.** Rejected by user; 4 green commits
  give per-workstream bisectability and reviewability.
- **WS4 — leave the god-object, only add `rubocop:disable`.** Rejected: that is the
  status quo the brief targets; the `tasks` backend proves the delegating pattern.

## Risks

- **ActiveStepLock churn (WS3) touches the live step-lock the orchestrator is using
  to drive THIS task.** Mitigation: behavior-preserving facade (same lock files,
  same semantics), full suite after the commit, and the lock's own specs.
- **Signature drift in WS4** could break callers. Mitigation: public Backend method
  signatures stay byte-stable; only private internals move; rspec + rubocop gate.
- **Coverage regression on new Api methods (WS3).** Mitigation: add specs in the
  same commit; verify api.rb stays 100%.
- **Version/CHANGELOG:** WS3 adds public `Api` methods → **minor** bump (additive);
  fold the single bump + CHANGELOG entry into commit 3 (or commit 4). WS1/WS2/WS4
  are internal-only.

## API

No public **CLI/JSON** contract change (pure refactor). Internal Ruby additions
only: new additive `Owl::Steps::Api` / `Owl::Subagents::Api` / `Owl::Tasks::Api` /
`Owl::Workflows::Api` facade methods replacing cli's direct `Internal::*` reaches,
plus shared `Owl::Internal::*` loader helpers. These are not user-facing surface;
they publish nothing to `docs/` beyond the realigned architecture doc 27.
