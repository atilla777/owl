---
status: resolved
verdict: accepted
ready: true
summary: >-
  `owl doctor [--fix]` lifecycle status-drift reconciler (v1.2.0) reviewed
  against brief AC, design API, and layering rules. Detection is read-only and
  reuses `TerminalStatus.workflow_complete?`; `--fix` reuses `Tasks::Api.set_status`
  (per-task lock + schema + index rebuild) with no new mutation path. Correctness,
  layering, idempotence, and edge cases all hold. Full `rspec` (2082 examples, 0
  failures) and `rubocop` (528 files, 0 offenses) green. No blocking findings.
---

# Summary

Self-review of the working-tree diff for TASK-0050 — `owl doctor [--fix]`, a
lifecycle status-drift reconciler that detects tasks whose workflow is
terminally complete (every step `done`/`skipped`) yet whose task-level `status`
is still a safely-promotable `open`/`in_progress`, and (under `--fix`) promotes
them to `done`.

Change surface:
- New `lib/owl/tasks/internal/drift_scanner.rb` — read-only `DriftScanner.scan`.
- New `lib/owl/cli/internal/commands/doctor.rb` — thin CLI wrapper.
- `lib/owl/tasks/api.rb` — additive public `lifecycle_drift(root:)` delegating to
  the scanner.
- `lib/owl/cli/api.rb` — registers `'doctor'` in `SIMPLE_COMMANDS`.
- `lib/owl/cli/internal/help_text.rb` — `doctor` help line.
- `lib/owl/version.rb` 1.1.3 → 1.2.0 (minor) + `CHANGELOG.md` 1.2.0 entry.
- Specs: `spec/owl/tasks/internal/drift_scanner_spec.rb`,
  `spec/owl/tasks/api_doctor_spec.rb`, `spec/owl/cli/internal/commands/doctor_spec.rb`.
- `tasks/TASK-0041/task.yaml` + `tasks/index.yaml`: TASK-0041 flipped `open → done`
  — the intended side effect of the `--fix` smoke test documented in the plan;
  not a code change.

Verdict: **accepted**. No unresolved blocking finding; completing the step.

# Findings

## Correctness vs brief AC & design API — PASS
- Drift predicate = `TerminalStatus.workflow_complete?(payload)` (all steps
  `done`/`skipped`) AND `payload['status'] ∈ {open, in_progress}`. Matches the
  brief's "terminal step done, status non-terminal & safely-promotable".
  `workflow_complete?` returns false for empty step lists, so step-less tasks are
  never flagged.
- `blocked`/`on_hold` excluded by `PROMOTABLE_STATUSES = %w[open in_progress]`;
  `done`/`archived`/`abandoned` excluded both at the index level
  (`candidate_entries` drops `TaskStatuses::TERMINAL`) and re-checked against the
  authoritative `task.yaml` payload in `drift_for` (defensive against a stale
  index). Never downgrades (only `open|in_progress → done`); never alters step
  status. Matches AC.
- Report-only by default; mutation only under explicit `--fix`. Orthogonality of
  `status` preserved.
- `--fix` idempotent by construction: a fixed task leaves the `{open,in_progress}`
  candidate set, so a second pass finds nothing — verified by the CLI spec.
- Output contract matches the design API exactly: report
  `{ok, drifted:[{task_id,status,workflow,terminal_step_id,suggested_status:"done"}], fixed:[]}`;
  `--fix` adds `fixed:[{task_id,from,to:"done"}]`. Exit 0 on success.

## Layering (docs/agents/27) — PASS
- `DriftScanner` lives in `Owl::Tasks::Internal` and consumes only Tasks-domain
  internals (`Paths`, `IndexReader`, `TaskReader`, `TaskStatuses`,
  `TerminalStatus`) — same-domain Internal access, allowed.
- `Commands::Doctor` (CLI domain) calls only the public `Owl::Tasks::Api`
  (`lifecycle_drift`, `set_status`) plus CLI-internal helpers (`JsonPrinter`,
  `TaskSupport`). No cross-domain `Internal::*` reach-through.
- No raw filesystem access outside the existing readers/writers; reads go through
  `IndexReader`/`TaskReader`, writes through `set_status` → `StatusWriter`.

## No new mutation path — PASS
- `--fix` calls `Owl::Tasks::Api.set_status(status: 'done')`, inheriting per-task
  `TaskMutationLock`, schema validation, and atomic `task.yaml` + `IndexWriter`
  rebuild. No hand-rolled writer. `set_status` errors surface via
  `TaskSupport.error_payload` with a non-zero exit (covered by the
  "surfaces a set_status error" spec).

## Coverage / api.rb gate — PASS
- `lib/owl/**/api.rb` 100% gate holds: full-run `rspec` exited 0 (the gate is
  full-run-scoped and would fail the suite otherwise). The new `lifecycle_drift`
  line is exercised directly by `spec/owl/tasks/api_doctor_spec.rb` (both the
  drift and empty-drift branches).

## Edge cases — PASS
- Composite parents mid-flow: gated `archive`/`commit_push` not yet `done` ⇒
  `workflow_complete?` false ⇒ not flagged. Correct (matches design risk note).
- Conditional `skipped` terminal steps count as complete via
  `WORKFLOW_DONE_STATUSES = %w[done skipped]`. Correct.
- `terminal_step_id` is reporting-only: picks the sink step no other step
  `requires`, falling back to `steps.last` for irregular graphs. Safe.

## Design/brief framing consistency — confirmed, not a defect
- Per the step note, `Steps::Internal::TaskFinalizer` already promotes new
  workflow-complete tasks to `done` at the terminal step. The design (Context +
  Alternative A1) explicitly reframes `owl doctor` as a backfill/safety-net
  reconciler for legacy/manually-reopened tasks rather than a missing-source-flip
  fix, and correctly flags the brief's "ничто не флипает status" as superseded.
  Framing between brief and design is consistent; this is intended scope.

## Minor (non-blocking, no change requested)
- `parse_options` accepts `--json` into `options[:json]` but never reads it —
  output is always JSON. This is consistent with the JSON-by-default convention
  across `bin/owl` (the flag is an accepted no-op), so it is intentional, not a
  defect.

# Resolution

All findings PASS; the single minor observation is intentional and matches
repo-wide convention, so no remediation is required. Verdict **accepted**, review
`status: resolved`.

Verification (independently re-run):
- `bundle exec rspec` — `2082 examples, 0 failures, 1 pending` (the pending is the
  long-standing SQLite concurrent-write contract placeholder, unrelated). Exit 0.
  Line coverage 97.14% overall; the `lib/owl/**/api.rb` 100% gate is satisfied
  (suite would otherwise fail).
- `bundle exec rubocop` — `528 files inspected, no offenses detected`. Exit 0.
- Read-only smoke: `bin/owl doctor --json` ⇒ `{"ok":true,"drifted":[],"fixed":[]}`
  (TASK-0041 already `done` from the implement-stage `--fix` smoke), confirming the
  empty-drift path and exit 0.

## Remediation

None required.

## Residual risks

- `done` is not `archived`: after `doctor --fix` a task is `done` but not
  physically archived; archival remains `owl archive`. Documented in the design
  and CHANGELOG, so `done`-without-archive is expected, not a bug.
- scan→fix race in parallel sessions: `StatusWriter` re-reads under the per-task
  lock; the worst case is setting `done` on an already-complete task, which is
  still correct. Acceptable.
