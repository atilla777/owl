# Goal

Add the `owl doctor [--fix]` command: a read-only lifecycle-drift scanner exposed
as `Owl::Tasks::Api.lifecycle_drift(root:)`, plus a thin CLI command that reports
status drift (workflow terminally complete, but `task.status ∈ {open, in_progress}`)
by default and reconciles it to `status: done` via the existing
`Tasks::Api.set_status` under `--fix`. Detection reuses
`Internal::TerminalStatus.workflow_complete?`; the fix path reuses `StatusWriter`
(per-task lock + index rebuild + schema), so no new mutation path is introduced.

# Checklist

- [ ] `lib/owl/tasks/internal/drift_scanner.rb` — new read-only module
  `Owl::Tasks::Internal::DriftScanner`. `scan(root:)`: resolve `Paths`, read
  `tasks/index.yaml` via `IndexReader`, select non-terminal entries
  (`!TaskStatuses::TERMINAL.include?(status)`), `TaskReader.read`/`read_task`
  each payload, flag drift when `TerminalStatus.workflow_complete?(payload)` is
  true AND `payload['status'] ∈ {open, in_progress}`. Return
  `Result.ok(drifted: [{task_id, status, workflow, terminal_step_id, suggested_status: 'done'}])`.
  `terminal_step_id` = the step no other step `requires` (fallback: last step id).
  No writes.
- [ ] `lib/owl/tasks/api.rb` — add public `lifecycle_drift(root:)` delegating to
  `Internal::DriftScanner.scan(root: root)` (add `require_relative` for the new
  internal). Read-only; 100%-covered public surface.
- [ ] `lib/owl/cli/internal/commands/doctor.rb` — new
  `Owl::Cli::Internal::Commands::Doctor` (pattern from `task_set_status.rb`).
  Parse `--fix`, `--json`, `--root` via `optparse`. Resolve root via
  `TaskSupport.resolve_root`. Call `Tasks::Api.lifecycle_drift`. Without `--fix`:
  print `{ok:true, drifted:[...], fixed:[]}`. With `--fix`: for each drifted task
  call `Tasks::Api.set_status(root:, task_id:, status: 'done')`, collect
  `{task_id, from, to:'done'}` into `fixed`; print `{ok:true, drifted:[...], fixed:[...]}`.
  Failures from `set_status` surface via `TaskSupport.error_payload`. Exit 0 on success.
- [ ] `lib/owl/cli/api.rb` — `require_relative 'internal/commands/doctor'` and add
  `'doctor' => Internal::Commands::Doctor` to the `SIMPLE_COMMANDS` table (after
  `self-update`).
- [ ] `lib/owl/cli/internal/help_text.rb` — add a `doctor` entry to the top-level
  command help listing so `owl --help` / help output documents it.
- [ ] `lib/owl/version.rb` — bump `Owl::VERSION` `1.1.3` → `1.2.0` (minor: new feature).
- [ ] `CHANGELOG.md` — add a `1.2.0` entry describing `owl doctor [--fix]`.

## Smoke test

```
# Drift exists (TASK-0041: quick workflow, all steps done, status:open)
bin/owl doctor --json
#   => {"ok":true,"drifted":[{"task_id":"TASK-0041","status":"open",...,"suggested_status":"done"}],"fixed":[]}
bin/owl task inspect TASK-0041 --json | grep -o '"status":"[a-z_]*"' | head -1   # still "open" (report-only)

bin/owl doctor --fix --json
#   => {"ok":true,"drifted":[...],"fixed":[{"task_id":"TASK-0041","from":"open","to":"done"}]}
bin/owl task inspect TASK-0041 --json | grep -o '"status":"[a-z_]*"' | head -1   # now "done"

bin/owl doctor --fix --json   # idempotent
#   => {"ok":true,"drifted":[],"fixed":[]}
```

NOTE: the smoke test mutates TASK-0041 to `status: done`. That is the intended
real-world reconciliation (TASK-0041 is genuinely terminally complete), so leaving
it `done` is correct — do not revert it.

## Scope

- New `owl doctor` command (top-level, flags `--fix`/`--json`/`--root`).
- New read-only `Owl::Tasks::Api.lifecycle_drift(root:)` + `DriftScanner` internal.
- `--fix` reconciles `open|in_progress → done` only for workflow-complete tasks,
  reusing `set_status`.
- Version bump + CHANGELOG.

## Constraints

- All `.owl/`/`tasks/`/`docs/` access through domain `Api`/`Internal` — never raw FS
  outside the existing readers/writers (`docs/agents/27_..._architecture.md`).
- Cross-domain calls go through public `Api` only; `DriftScanner` lives inside the
  Tasks domain so it may use Tasks `Internal::*` directly.
- The fix path must reuse `Tasks::Api.set_status` (lock + index + schema); do NOT
  hand-write a status mutation.
- Never touch `blocked`/`on_hold`/`done`/`archived`/`abandoned`; never downgrade
  status; never alter step statuses.
- Bump `Owl::VERSION` + CHANGELOG in the same commit (Constitution §7.1).
- `lib/owl/tasks/api.rb` keeps 100% line coverage
  (`docs/agents/30_..._public_API_coverage.md`).

## Files to inspect

- `lib/owl/tasks/internal/terminal_status.rb` — `workflow_complete?` predicate.
- `lib/owl/tasks/internal/task_statuses.rb` — `TERMINAL` set.
- `lib/owl/tasks/internal/availability_scanner.rb` — index enumeration + `read_task` pattern.
- `lib/owl/tasks/internal/status_writer.rb` — confirms `set_status` does lock+index+schema.
- `lib/owl/cli/internal/commands/task_set_status.rb` — CLI command template.
- `lib/owl/cli/api.rb` (`SIMPLE_COMMANDS`, requires).
- `lib/owl/tasks/api.rb` (`read_task`, `with_backend`, public method style).

## Tests and verification

- `spec/owl/tasks/internal/drift_scanner_spec.rb` — drift detected for
  workflow-complete + `open`/`in_progress`; NOT for `blocked`/`on_hold`/terminal
  statuses; NOT for incomplete workflows (pending step); composite parent mid-flow
  not flagged; report-only (no disk mutation).
- `spec/owl/tasks/api_doctor_spec.rb` (or extend `api_spec.rb`) — `lifecycle_drift`
  returns the drifted list; covers the new public lines (100% for `api.rb`).
- `spec/owl/cli/internal/commands/doctor_spec.rb` — `--json` report shape & no
  mutation; `--fix` sets `done` + `fixed[]` payload; idempotent second run;
  `set_status` error surfaced.
- Run `bundle exec rspec` (full run for SimpleCov gate) and `bundle exec rubocop`;
  both must be green. Run the Smoke test block above against the live repo.

## Out of scope

- Broad health-check (index↔task.yaml resync, stale active-step locks, expired
  claims, orphan current-pointer, broken artifact refs) — explicitly deferred.
- Source-side lifecycle change (auto-setting `status=done` at the terminal
  step/workflow completion).
- Moving tasks to the archive store (`archived`) — that stays with `owl archive`.
- Reverse drift (`status` terminal but steps incomplete) — not auto-fixed; at most
  an informational note, not in this task's `--fix`.
