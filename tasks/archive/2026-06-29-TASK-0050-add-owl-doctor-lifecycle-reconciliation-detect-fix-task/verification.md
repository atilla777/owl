---
status: passed
summary: >-
  owl doctor [--fix] implemented (DriftScanner + Tasks::Api.lifecycle_drift + CLI
  command, v1.2.0). Full rspec green (2082 examples, 0 failures), rubocop clean
  (528 files, 0 offenses), live smoke test detected and fixed TASK-0041 drift
  idempotently.
---

## Summary

Added `owl doctor [--fix]`, a read-only lifecycle status-drift reconciler. New
`Owl::Tasks::Internal::DriftScanner` flags non-terminal index tasks whose
workflow is terminally complete (`TerminalStatus.workflow_complete?`) but whose
`status ∈ {open, in_progress}`; exposed read-only via
`Owl::Tasks::Api.lifecycle_drift(root:)`. New CLI command
`Owl::Cli::Internal::Commands::Doctor` (registered in `SIMPLE_COMMANDS` + help
text) reports drift by default and, with `--fix`, promotes each drifted task to
`done` by reusing the existing `Tasks::Api.set_status` writer (per-task lock +
schema + index rebuild — no new mutation path). Version bumped 1.1.3 → 1.2.0 with
a CHANGELOG entry. Specs added for the scanner, the public API method, and the
CLI command (report-only no-mutation, `--fix`, idempotence, set_status error
surfaced).

Notable finding during verification: `Owl::Steps::Internal::TaskFinalizer`
already promotes a workflow-complete non-terminal task to `done` at the source
when its terminal step completes (the "A1" source-side fix the brief described as
rejected). New completions therefore do not drift; `owl doctor` functions as a
backfill / safety-net reconciler for legacy tasks (e.g. the pre-finalizer
TASK-0041) and for tasks manually re-opened after completion. Scope was kept
exactly as specified in the plan/design.

## Commands

- `bundle exec rspec spec/owl/tasks/internal/drift_scanner_spec.rb spec/owl/tasks/api_doctor_spec.rb spec/owl/cli/internal/commands/doctor_spec.rb` (focused, during iteration)
- `bundle exec rspec` (full run — SimpleCov public-API gate is full-run-scoped)
- `bundle exec rubocop` (full tree)
- `bin/owl doctor --json` (live smoke — report-only)
- `bin/owl doctor --fix --json` (live smoke — reconcile)
- `bin/owl doctor --fix --json` (live smoke — idempotent second run)
- `bin/owl task inspect TASK-0041 --json | grep -o '"status":"[a-z_]*"' | head -1` (before/after status)
- `bin/owl --help` (doctor entry present)

## Outcomes

- Focused new specs: 13 examples, 0 failures.
- Full suite: `2082 examples, 0 failures, 1 pending` (the pending is the
  pre-existing SQLite concurrent-write contract placeholder, unrelated). Line
  Coverage 97.14% (11606/11948); the public-API 100% gate did not trip —
  `lib/owl/tasks/api.rb` new `lifecycle_drift` line is covered.
- RuboCop: `528 files inspected, no offenses detected`.
- Live smoke test (exact JSON):
  - `bin/owl doctor --json` →
    `{"ok":true,"drifted":[{"task_id":"TASK-0041","status":"open","workflow":"quick","terminal_step_id":"commit_push","suggested_status":"done"}],"fixed":[]}`
  - TASK-0041 status before fix: `"status":"open"` (report-only did not mutate).
  - `bin/owl doctor --fix --json` →
    `{"ok":true,"drifted":[{"task_id":"TASK-0041","status":"open","workflow":"quick","terminal_step_id":"commit_push","suggested_status":"done"}],"fixed":[{"task_id":"TASK-0041","from":"open","to":"done"}]}`
  - TASK-0041 status after fix: `"status":"done"`.
  - `bin/owl doctor --fix --json` (second run) → `{"ok":true,"drifted":[],"fixed":[]}` (idempotent).
- `Owl::VERSION` is `1.2.0`; `owl --help` lists the `doctor` command.

## Not run

The `bin/owl version` command still reports the installed gem (1.1.3) rather than
the checkout 1.2.0 — that is expected (it reflects the on-PATH gem, propagated
later via gem rebuild), not part of this step. No gem build / `owl upgrade` was
run (out of scope; the later `commit_push` step and propagation handle release).

## Failures or blockers

None. (RSpec exits non-zero with 0 failures is a known repo wart; the example/
failure counts and the green SimpleCov gate are the real signal — both green.)

## Residual risks

- The smoke test intentionally reconciled the real TASK-0041 to `status: done`;
  this is the correct real-world outcome (TASK-0041 is terminally complete) and
  is left as-is per the plan.
- scan→fix is not atomic across parallel sessions: a concurrent status change
  between scan and `set_status` could promote a task that is still
  `workflow_complete?`; `StatusWriter` re-reads under lock and the worst case is
  a correct `done`. No additional re-check was added (matches the plan).
- `done ≠ archived`: a doctor-fixed task is `done` but not physically archived;
  archival remains with `owl archive` (documented in the CHANGELOG/brief).
