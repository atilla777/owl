---
status: approved
summary: "Register a spec_delta artifact type, declare it optional in the feature workflow, add Owl::Specs::Api.merge_task (graceful no-delta skip; P4 apply; P5 trace --strict gate) + owl spec merge CLI, and update the merge_docs context to invoke it — backward-compatible for spec-less tasks."
---

# Context

P4 gives `Owl::Specs::Api.apply(root:, domain:, delta_path:, dry_run:)` and the
`SpecDocument/SpecDelta/DeltaMerger` engine; P5 gives `Owl::Specs::Api.trace(root:, domain:,
strict:)`. P1 gives domain slug-validation + `specs` storage role. The `feature` workflow's
`merge_docs` step is execution, driven by its context file (`.owl/workflows/feature/
merge_docs.context.md` + seed copy), and currently instructs running `owl publish` (a no-op here).
Artifact types are declared in `.owl/artifacts/<key>/artifact.yaml` (+ repo-root seed) and listed
in `.owl/artifacts.yaml`; a workflow's `artifacts:` map binds an artifact key to storage. The P4
delta format already parses `## ADDED|MODIFIED|REMOVED Requirements`.

# Decision

**1. `spec_delta` artifact type.** Scaffold `.owl/artifacts/spec_delta/artifact.yaml` (+ seed +
`templates/default.md`):
- front matter: required `domain` (string) + `status` (enum `draft|merged`).
- `validation.required_sections`: none mandated as a set (a delta may use any subset of
  ADDED/MODIFIED/REMOVED); instead a `required_patterns` entry mandating at least one
  `(?m)^## (ADDED|MODIFIED|REMOVED) Requirements` heading so an empty delta fails early.
- template seeds a `domain`, a `## ADDED Requirements` with one `### Requirement:` + `####
  Scenario:` (WHEN/THEN/`- TEST:`) so a fresh delta is valid and shows the format.
Register in `.owl/artifacts.yaml` (+ seed `artifacts.yaml`).

**2. Declare `spec_delta` optional in the feature workflow.** Add it to the workflow's `artifacts:`
map with storage `role: tasks, path: "{{task.id}}/spec_delta.md"`. No step lists it under
`creates:` (it is produced on demand), so it stays optional and absent by default. (Confirm the
workflow validator accepts an artifact declared but not created by a step; if not, attach it as a
`uses_if_present` on merge_docs.)

**3. `Owl::Specs::Api.merge_task(root:, task_id:, dry_run: false)`** (public api.rb → 100% cov) +
`lib/owl/specs/internal/task_merger.rb`:
- Resolve the task's spec_delta path via `Owl::Artifacts::Api.resolve(root:, task_id:, artifact_key:
  'spec_delta')` (or storage path `tasks/<id>/spec_delta.md`). If absent → `Result.ok(applied:
  false, reason: 'no_spec_delta')`.
- Read front matter `domain`; missing → `spec_delta_missing_domain`; slug-invalid → `invalid_domain`.
- Apply: call `Specs::Api.apply(root:, domain:, delta_path:, dry_run:)` (P4) — propagates
  `delta_conflict`/`delta_target_missing`/`invalid_delta`/`merge_would_invalidate`.
- Gate: call `Specs::Api.trace(root:, domain:, strict: true)` (P5) on the resulting spec.
- Return `{ok: trace.valid, applied: !dry_run, domain:, merge: {...}, trace: {...}}`. `ok:false`
  when trace gate fails (untraced/dangling), but the delta remains applied (documented).
- `dry_run: true` → apply in preview mode (no write) and trace the would-be body if the engine
  supports previewing a body; otherwise trace the current on-disk spec and mark `applied:false`.

**4. CLI `owl spec merge TASK-ID [--dry-run] [--json]`** — `lib/owl/cli/internal/commands/
spec_merge.rb` mirroring sibling spec commands; positional `<TASK-ID>`; wired into `dispatch_spec`;
non-JSON prints a readable apply+trace summary; update HELP_TEXT.

**5. Wire `merge_docs`.** Update `.owl/workflows/feature/merge_docs.context.md` (+ seed) to instruct
the executor: run `owl publish TASK-ID` (existing) AND `owl spec merge TASK-ID`; a `no_spec_delta`
skip or `no_publishable_step` is a normal no-op; a delta present is applied and the trace gate must
pass. (Context-only change; no engine code in the step.) Document that this keeps spec-less tasks a
no-op.

# Alternatives

- **Auto-generate the delta from the design artifact via LLM** — rejected: reintroduces
  non-determinism P4 removed. The delta is an authored artifact; merge is deterministic.
- **Make spec_delta a required step output** — rejected: would force every task (incl. tooling
  tasks like this one) to touch a spec; optional + graceful-skip preserves backward compatibility.
- **Roll back the applied delta on trace failure** — rejected: the merged spec is the new contract;
  trace failure means "tests not linked yet", a gate signal, not a reason to discard the contract
  change. Documented; `--dry-run` is available to preview before committing.
- **Put merge logic in the merge_docs subagent prompt only** — rejected: the deterministic core
  belongs in a CLI (`owl spec merge`); the step just invokes it.

# Risks

- **Workflow validator rejecting an artifact with no creating step** — mitigated: fall back to
  `uses_if_present` on merge_docs; covered by `owl workflow validate feature` in tests.
- **merge_docs behavioural change for existing tasks** — mitigated: `no_spec_delta` graceful skip +
  an integration test asserting a spec-less task's merge_docs writes nothing.
- **dry-run still writing** — mitigated: delegate to P4 `apply(dry_run:true)` which is already
  no-write (tested in P4); add a no-write assertion here too.
- **api.rb coverage** — exercise `merge_task` ok/err/skip/dry-run through the Api/CLI path.
- **Seed/active drift** for the new artifact type + merge_docs context — update both; seed-parity
  suite guards it.

# API

New public: `Owl::Specs::Api.merge_task(root:, task_id:, dry_run: false) -> Result`.
New internal: `Owl::Specs::Internal::TaskMerger`.
New artifact type: `spec_delta` (markdown). New optional workflow artifact `spec_delta` in
`feature`. New CLI: `owl spec merge TASK-ID [--dry-run] [--json]`. Errors: `spec_delta_missing_domain`,
`invalid_domain`, plus propagated P4 delta errors. merge_docs context updated to invoke it.
`lib/owl/specs/api.rb` requires 100% line coverage.
