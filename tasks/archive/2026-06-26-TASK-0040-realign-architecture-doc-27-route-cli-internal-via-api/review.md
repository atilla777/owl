---
status: resolved
summary: TASK-0040's 4-commit behavior-preserving refactor verified — suite 1998/0/1, api.rb 100%, signatures byte-stable, cli→Internal eliminated, loaders deduped, backend 803→223. One non-blocking doc-staleness follow-up in doc 27.
verdict: accepted_with_followups
ready: true
---

# Review

## Summary

Independent review of TASK-0040 (4 commits `0713477`→`d2c1ca6`, already pushed to
main): a behavior-preserving maintainability refactor across four workstreams —
doc 27 realignment, loader dedup, cli→Api facades, and workflows-backend
decomposition. I re-ran every acceptance check from `brief.md` and the plan
against the real diffs (`8bb340f..HEAD`). The refactor is sound: the full suite is
green, public-API coverage stays at 100%, all externally-called signatures are
byte-stable, the cli no longer reaches into domain `Internal::*`, the loader trio
is genuinely deduplicated with field mappings preserved, and the backend
god-object is a clean delegator. The live CLI (which dogfoods this task) works.

Verdict: **accepted_with_followups**. Every enumerated acceptance criterion
passes with zero behavior regression. I found one minor, documentation-only drift:
doc 27 still carries a "current state" note describing a debt that WS3 (in this
same task) eliminated. It is cosmetic and non-behavioral, so it does not block,
but it is exactly the doc-vs-reality gap this task set out to close and is worth a
one-line follow-up edit.

## Findings

- [ ] **MINOR (docs)** — `docs/agents/27_Owl_Ruby_code_architecture.md` ~lines
  140-155: the "Заметка о текущем состоянии" claims "в `lib/owl/cli/` остаётся
  ~24 прямых обращения в доменный `Internal::*` … это долг, который выпрямляется
  отдельным workstream-ом". That workstream is WS3 of THIS task; after commit
  `94b0e8a`, `grep -rn '::Internal::' lib/owl/cli/ | grep -v 'Cli::Internal::'` →
  0. The note was accurate when written in commit 1 but is stale post-WS3, so the
  shipped doc now under-reports reality (says 24 reaches remain when 0 do).
  Severity: low (non-behavioral, self-correcting once read against code).
- Criterion 1 — No regression: PASS. `bundle exec rspec` → **1998 examples, 0
  failures, 1 pending** (real parsed numbers, not exit code). The lone pending is
  the pre-existing SQLite concurrent-write placeholder in
  `spec/owl/storage/backends/shared/backend_contract.rb`, unrelated.
- Criterion 2 — api.rb 100% coverage: PASS. The full-suite output contains no
  "below 100%" / public-API-gate warning line (grepped the captured run for
  `below 100|public api|api\.rb|100%` → none). 14 new facade specs cover every
  added Api method.
- Criterion 3 — WS3 cli→Api: PASS. `grep` for cli cross-domain `Internal::` →
  0 matches. Spot-checked `Steps::Api.active_step_lock_*`, `detect_drift`,
  `drift_policy_for`, `Subagents::Api.{report_schema,validate_report,report_path}`,
  `Tasks::Api.{resolve_paths,read_task}`, `Workflows::Api.step_context_frontmatter_check_key`
  — all are genuine pass-throughs (same kwargs, same Result/return shape, no logic
  added). Each new api.rb line is exercised by `spec/owl/{steps,subagents,tasks,
  workflows}/api*facades*spec.rb`.
- Criterion 4 — WS2 loaders: PASS. `default_template.rb` (both domains) untouched
  (not force-deduped). Shared `Owl::Internal::{YamlCache,SourceLoader,RegistryLoader}`
  exist; domain copies are thin delegators. Field mappings differ and are
  preserved: artifacts `SourceLoader::FIELDS` = title/kind/description vs workflows
  = description||title / kind; artifacts registry has no extra top-level field vs
  workflows passing `top_level: { default_workflow: 'default_workflow' }`. Result
  hash key ordering preserved.
- Criterion 5 — WS4 backend split: PASS. `wc -l
  lib/owl/workflows/backends/filesystem.rb` = **223** (≤300); ClassLength disable
  count = **0**. Backend public method signatures byte-stable vs `8bb340f` (diffed
  every `def`): `registry/list/find/scaffold/validate/source_show/register/
  unregister/context_show/context_set/graph/definition/ready_steps/
  read_step_context[_frontmatter]/local_paths_for/seeded_sources/default_template`
  all identical. The methods that moved out (gating helpers, scaffold/validate
  internals) were private helpers, not part of the `workflows/backend.rb`
  interface contract. Logic delegated to `Internal::*`; Result.err branches
  preserved.
- Criterion 6 — WS1 doc 27: PASS (modulo the finding above). The universal-funnel
  "весь FS I/O через `Owl::Storage::Api`" claim is gone; remaining `Storage::Api`
  mentions are as one domain among many (`Owl::<Domain>::Api`) or in legitimate
  BackendResolver bootstrap-exception context. Doc now describes the
  api→backend→backends/filesystem→internal→local pattern and the `Owl::Internal::*`
  bootstrap exceptions.
- Criterion 7 — rubocop: PASS. Net offenses on `lib/owl/` went 28 → 26 (the
  removed ClassLength disable + decomposed god-object reduced count). All files
  touched by this task are clean; remaining offenses live in untouched files
  (`workflow_validator.rb`, `config_set.rb`, `task_list.rb`,
  `workflow_diagram_data.rb`, `subagents/api.rb:spawn` [pre-existing on the old
  `spawn` method, not the new facades], etc.). No NEW offense introduced.
- Criterion 8 — version/CHANGELOG: PASS. `lib/owl/version.rb` = `0.22.0` (minor,
  correct for additive Api surface). CHANGELOG `[0.22.0] - 2026-06-26` entry
  accurately enumerates all four workstreams and the new Api methods.
- Criterion 9 — live smoke: PASS. `bin/owl next/status/ready-steps TASK-0040
  --json` and `bin/owl workflow show feature` all return `ok:true` with
  well-formed payloads. (Note: TASK-0040 runs the `refactor` workflow, not
  `feature`.)
- Criterion 10 — suspicious-change scan: CLEAN. No dropped error handling, no lost
  `Result.err` branches, require_relative paths resolve, no leftover debug code.

## Resolution

- Finding 1 (stale doc-27 transitional note): **deferred** as a fast follow-up.
  Non-blocking, documentation-only, no behavior impact; recommend deleting/
  updating the "Заметка о текущем состоянии" paragraph since WS3 already made the
  target rule the actual state. Would warrant a tiny docs-only patch (no version
  bump — `docs/**` is out of scope per Constitution §7.1).
- All other criteria: **accepted** as verified — no changes owed.

## Remediation

- Edit `docs/agents/27_Owl_Ruby_code_architecture.md` (~lines 140-155): drop or
  rewrite the "~24 reaches remain / debt being straightened" note so the doc
  states the cli→`<Domain>::Api`-only rule as the realized state (it is, as of
  `94b0e8a`). Docs-only, no version bump.

## Residual risks

- WS3 fronts `ActiveStepLock` with pass-through facades rather than redesigning
  the lock protocol; behavior is identical but a future task could introduce a
  higher-level `with_active_step_lock` API if the fine-grained primitives prove
  leaky. (Carried from verification.md; acceptable.)
- The 4 pre-existing rubocop offenses in
  `lib/owl/workflows/internal/workflow_validator.rb` (ModuleLength + complexity on
  `validate_step_variants`) are untouched separate debt, out of scope here.
- No new concurrency surface: the facades are pure pass-throughs over the existing
  lock/heartbeat code, whose specs stayed green.
