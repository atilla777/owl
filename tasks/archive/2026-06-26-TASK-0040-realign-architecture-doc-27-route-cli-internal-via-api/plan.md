---
status: approved
summary: Execute the 4-workstream refactor as 4 sequential green commits — doc 27, loader dedup, cli→Api, workflows-backend split — each verified by full rspec + rubocop before commit.
---

# Plan

## Goal

Deliver TASK-0040's behavior-preserving refactor (see design) as 4 sequential
commits, each leaving `bundle exec rspec` at 0 failures, `api.rb` at 100% line
coverage, and RuboCop clean. Single minor `Owl::VERSION` bump (additive Api
methods) + CHANGELOG, folded into the cli→Api commit.

## Scope

- `docs/agents/27_Owl_Ruby_code_architecture.md` (WS1).
- `lib/owl/internal/*` + `lib/owl/{artifacts,workflows}/internal/{cache,source_loader,seeded_sources,registry_loader}.rb` (WS2).
- `lib/owl/cli/**` + `lib/owl/{steps,subagents,tasks,workflows}/api.rb` + matching specs (WS3).
- `lib/owl/workflows/backends/filesystem.rb` + new `lib/owl/workflows/internal/*` (WS4).
- `lib/owl/version.rb` + `CHANGELOG.md`.

## Constraints

- Behavior-preserving: NO change to `bin/owl` CLI/JSON output, exit codes, or on-disk format.
- Public Backend method signatures stay byte-stable (WS4); new Api methods are additive (WS3).
- Loader dedup preserves each domain's distinct field mappings (`registry_loader`); `default_template` left separate.
- `Cli::Internal::*` (cli's own internal) is NOT a cross-domain reach — leave it.
- Doc 27 stays Russian (matches the rest of `docs/agents/`).
- Suite green + rubocop clean + api.rb 100% BEFORE each commit.

## Checklist

### Commit 1 — WS1 doc 27 (docs only)
- [ ] Rewrite doc 27 around the real per-domain backend pattern (api → backend → backends/filesystem → internal; local.rb for runtime paths).
- [ ] Remove the stale "все FS через `Owl::Storage::Api`" claim; document the `Owl::Internal::*` bootstrap exceptions (BackendResolver/Cache/Paths/SeededLoader/GemAssets) and the "cli calls only `<Domain>::Api`" rule.
- [ ] Verify: `rspec` green (docs change is inert), commit `docs: realign architecture doc 27 with per-domain backend pattern (TASK-0040)`, push.

### Commit 2 — WS2 loader dedup
- [ ] Collapse `cache` / `source_loader` / `seeded_sources` domain copies into the shared `Owl::Internal::*` helper (domain copies delegate, or are removed if the existing shared one suffices). Update requires/callers.
- [ ] `registry_loader`: extract shared skeleton, pass each domain's field mapping in; keep distinct fields intact.
- [ ] Leave `default_template` separate (divergent bodies).
- [ ] Verify: `rspec` green, rubocop clean. Commit `refactor: collapse artifacts/workflows loader duplication into Owl::Internal (TASK-0040)`, push.

### Commit 3 — WS3 cli → Api facades (+ version bump)
- [ ] Add additive Api methods for each cross-domain reach: `Steps::Api` lock facade (acquire/release/with-lock) for ActiveStepLock; `Steps::Api` for DriftDetector/DriftPolicy; `Subagents::Api` for OutputSpec/ReportPaths; `Tasks::Api` for TaskReader/Paths; `Workflows::Api` for StepContextFrontmatterCheck.
- [ ] Replace every `lib/owl/cli/**` `<Domain>::Internal::*` reach with the Api call (leave `Cli::Internal::*`).
- [ ] Add specs covering every new api.rb line → api.rb back to 100%.
- [ ] Bump `Owl::VERSION` minor + CHANGELOG entry (covers the whole TASK-0040).
- [ ] Verify: `grep -rn '::Internal::' lib/owl/cli/ | grep -v 'Cli::Internal'` → 0; `rspec` green; api.rb 100%; rubocop clean. Commit `refactor: route cli through domain Api facades, not Internal (TASK-0040)`, push.

### Commit 4 — WS4 workflows backend split (riskiest)
- [ ] Extract the inline private logic into `workflows/internal/*` per design (ready_resolver gating, scaffolder, validation_loader, step_context_resolver context ops, registry_writer, errors); backend delegates.
- [ ] Keep public Backend signatures byte-stable; no file > ~300 lines without justification.
- [ ] Verify: `wc -l lib/owl/workflows/backends/filesystem.rb` materially reduced; `rspec` green; rubocop clean (drop the `Metrics/ClassLength` disable if no longer needed). Commit `refactor: decompose workflows filesystem backend into internal services (TASK-0040)`, push.

## Tests and verification

- After EACH commit: `bundle exec rspec` → report real failure count (repo can exit red with 0 failures); `bundle exec rubocop` clean; `lib/owl/**/api.rb` coverage 100%.
- `grep -rn '::Internal::' lib/owl/cli/ | grep -v 'Cli::Internal::'` → 0 (after commit 3).
- `grep -ni 'Storage::Api' docs/agents/27_Owl_Ruby_code_architecture.md` → no stale "all FS" claim (after commit 1).
- Diff the loader pairs after commit 2 to confirm dedup landed without losing field mappings.

## Smoke test

`bundle exec rspec` is green and `bin/owl status TASK-0040 --json` still works after each commit (the tool dogfoods itself — a broken refactor would break the very CLI driving this task).

## Out of scope

- Any `bin/owl` behavior, CLI flag, or JSON-shape change.
- Deduping `default_template` (genuinely divergent).
- Touching `Cli::Internal::*` (cli's own internals).
- Refactoring domains other than the workflows backend in WS4.

## Files to inspect

- `lib/owl/tasks/backends/filesystem.rb` (the clean delegating model to mirror).
- `lib/owl/workflows/internal/ready_resolver.rb`, `step_context_resolver.rb` (existing extraction targets).
- `lib/owl/steps/api.rb` (where the ActiveStepLock facade lands; currently 370 lines, 100% covered).
- The loader pairs under `lib/owl/{artifacts,workflows}/internal/` and the existing `lib/owl/internal/{cache,seeded_loader}.rb`.
