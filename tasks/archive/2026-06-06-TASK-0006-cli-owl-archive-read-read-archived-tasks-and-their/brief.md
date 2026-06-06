---
status: approved
summary: Add read-only CLI to list archived tasks and read their artifacts, so agents/humans can audit completed work and debug Owl without un-archiving or reading tasks/archive/ files directly.
---

# Problem

Owl can archive a completed task (`owl archive TASK-ID` moves
`tasks/<ID>/` → `tasks/archive/<date>-<ID>-<slug>/`), but there is **no CLI to read it
back**. The whole `bin/owl` surface (`task list/inspect`, `status`, `artifact resolve/validate`)
operates on the live `tasks/` zone; once a task is archived it falls off every command.

This breaks two needs:

1. **Quality auditing** — an agent reviewing or extending past work (e.g. P2 needs the
   `forbid_empty_sections`+`require_scenarios` composition note recorded in TASK-0001's archived
   `review.md`) cannot retrieve those artifacts through the CLI.
2. **Debugging Owl itself** — inspecting how a finished task progressed requires hand-reading
   `tasks/archive/...`, violating the architectural invariant that all task state is read
   through `bin/owl`.

# Goal

Add a read-only archive surface to `bin/owl` that lists archived tasks and reads their
`task.yaml` payload and artifact bodies, **without** un-archiving and **without** changing the
existing `owl archive TASK-ID` archive verb. JSON-first, consistent with existing command
shapes.

Proposed surface (final names per design):

- `owl archive list [--json]` — enumerate archived tasks.
- `owl archive show <TASK-ID> [--json]` — archived `task.yaml` payload + artifact inventory.
- `owl archive read <TASK-ID> <ARTIFACT-KEY> [--json]` — body of one archived artifact.
- `owl archive <TASK-ID>` — UNCHANGED archive verb (backward compatible).

# Scenarios

### Requirement: List archived tasks

The CLI SHALL enumerate every archived task under the archive storage role.

#### Scenario: List with archived tasks present
- WHEN the user runs `owl archive list --json` and ≥1 task has been archived
- THEN the output is `{ok:true, archived:[{task_id, slug, archived_date, title, path}, ...]}`
- AND each entry resolves to an existing directory under the archive role

#### Scenario: List when none archived
- WHEN no task has been archived
- THEN the output is `{ok:true, archived:[]}` (success, empty list — not an error)

### Requirement: Show an archived task

The CLI SHALL return the archived task payload and its artifact inventory by TASK-ID.

#### Scenario: Show existing archived task
- WHEN the user runs `owl archive show TASK-0001 --json` for an archived task
- THEN the output includes the task id, title, workflow, status, step states, and a list of
  available artifact keys with their paths
- AND it does NOT move or modify any file

#### Scenario: Show unknown / non-archived id
- WHEN the TASK-ID is not present in the archive
- THEN the CLI returns a structured `archived_task_not_found` error (non-zero), not a crash

### Requirement: Read an archived artifact body

The CLI SHALL return the raw body of a named archived artifact.

#### Scenario: Read existing artifact
- WHEN the user runs `owl archive read TASK-0001 review --json`
- THEN the output is `{ok:true, task_id, artifact_key, path, body}` with the file contents
- AND for non-JSON mode the raw body is printed to stdout

#### Scenario: Read missing artifact key
- WHEN the artifact key does not exist for that archived task
- THEN the CLI returns a structured `archived_artifact_not_found` error listing available keys

### Requirement: Archive verb stays backward compatible

The system SHALL keep `owl archive <TASK-ID>` archiving a live task exactly as before.

#### Scenario: Bare task id still archives
- WHEN the user runs `owl archive TASK-0007` where the arg is not a known read subcommand
- THEN the existing archive behaviour runs and returns the existing archive payload
- AND existing archive specs pass unchanged

# Edge cases

- A `<TASK-ID>` arg that collides with a subcommand name is impossible (task ids are
  `TASK-NNNN`, subcommands are `list|show|read`) — dispatcher checks the known subcommand set
  first, else treats the arg as a TASK-ID for the archive verb.
- Archive directory name carries date+slug; lookup must match by embedded TASK-ID, tolerant of
  the date/slug prefix and any `collision_suffix`.
- Multiple archives of the same logical id (collision suffix) — `show`/`read` must resolve
  deterministically (e.g. most recent, or error listing candidates); decided at design.
- Artifact key discovery: derive from files present in the archived dir (e.g. `review.md` →
  key `review`) and/or the archived `task.yaml` artifact map; design picks the source of truth.
- Read-only guarantee: none of the new subcommands may write, move, or delete anything.

# Acceptance criteria

- [ ] `owl archive list`, `owl archive show <id>`, `owl archive read <id> <key>` implemented,
      JSON-first, with non-JSON fallbacks consistent with sibling commands.
- [ ] `owl archive <TASK-ID>` archive verb unchanged; existing archive specs green.
- [ ] New read APIs live in `Owl::Archive` (or a new internal reader) and go through storage
      roles, never hard-coded paths.
- [ ] Structured errors `archived_task_not_found` / `archived_artifact_not_found` with helpful
      details (available ids / keys).
- [ ] RSpec coverage for list/show/read happy paths, empty list, unknown id, missing key, and
      the backward-compatible archive verb dispatch.
- [ ] `bundle exec rspec` green; `bundle exec rubocop` clean on changed files (never `-A`).
- [ ] 100% line coverage maintained for any touched `lib/owl/**/api.rb`.
