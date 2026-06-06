---
status: passed
summary: owl archive list/show/read read-only CLI implemented and verified; full suite 0 failures, rubocop clean, archive/api.rb at 100% line coverage, archive verb backward-compatible.
---

## Summary

Added a read-only archive surface to `bin/owl` while keeping the existing
`owl archive <TASK-ID>` archive verb unchanged:

- `owl archive list` / `show <TASK-ID>` / `read <TASK-ID> <ARTIFACT-KEY>`.
- New internal `Owl::Archive::Internal::ArchiveReader` resolves the archive
  storage-role dir via `Owl::Storage::Api` (not hard-coded `tasks/archive`),
  scans `^(\d{4}-\d{2}-\d{2})-(TASK-\d+)-(.+)$`, skips non-matching dirs,
  newest-wins on collisions. Artifact-key discovery from the archived
  `task.yaml` artifact map when a non-empty Hash, else `*.md` filename stems.
- New public methods `list/show/read` on `Owl::Archive::Api` (delegation;
  `archive_task` unchanged).
- Three CLI command modules (`ArchiveList`/`ArchiveShow`/`ArchiveRead`) wired
  through a new `dispatch_archive` sub-dispatcher in `lib/owl/cli/api.rb`;
  `read --no-json` prints the raw artifact body to stdout.
- Structured errors `archived_task_not_found` (with `available_ids`) and
  `archived_artifact_not_found` (with `available_keys`).
- All filesystem access is funneled through `Owl::Storage::Api`; added a
  `children(path:)` enumerator to the storage facade + filesystem backend so
  the reader does no direct `File`/`Dir`/`Pathname.new` I/O (passes the
  constitution `no_direct_fs` meta-spec).

## Commands

- `bundle exec rspec` — full suite.
- `bundle exec rspec spec/owl/archive spec/owl/cli/archive_read_command_spec.rb spec/owl/cli/archive_command_spec.rb` — targeted.
- `bundle exec rubocop <changed lib + spec files>` — lint.
- Live smoke against the real archived TASK-0001:
  `bin/owl archive list --json`, `bin/owl archive show TASK-0001 --json`,
  `bin/owl archive read TASK-0001 review --json|--no-json`,
  `bin/owl archive read TASK-0001 nope --json`, `bin/owl archive show TASK-9999 --json`.

## Outcomes

- `bundle exec rspec`: 1264 examples, 0 failures, 1 pending (pre-existing
  pending: SQLite backend concurrent-write contract).
- Coverage gate: only `lib/owl/steps/api.rb` is below 100% line coverage
  (99.16%) — this is PRE-EXISTING on clean `main` (identical before this task,
  verified via `git stash`) and unrelated to archive. The task's target file
  `lib/owl/archive/api.rb` is at **100% line coverage** (every new method
  exercised, ok + err branches via the API path); `lib/owl/storage/api.rb`
  (touched by the new `children` method) is also at 100%.
- `bundle exec rubocop` on all 12 changed/new files: **no offenses detected**
  (no `-A` used; fixed `Style/MultilineBlockChain` and `Metrics/ModuleLength`
  by hand, used anonymous `**` keyword forwarding in `dispatch_archive`).
- Constitution `no_direct_fs` meta-spec: passes (reader routes all FS access
  through `Owl::Storage::Api`).
- Live smoke: `list` returns TASK-0001; `show` returns steps + artifact
  inventory `[brief, design, plan, review, verification]`; `read review`
  returns the body (JSON and raw); `read nope` → `archived_artifact_not_found`
  with `available_keys`; `show TASK-9999` → `archived_task_not_found` with
  `available_ids`.
- Backward compatibility: existing `spec/owl/cli/archive_command_spec.rb` and
  `spec/owl/archive/api_spec.rb` archive-verb tests pass unchanged; a new test
  asserts `owl archive <TASK-ID>` still archives a live task.
- Note: 8 "circular require" warnings emitted during the archive specs are
  PRE-EXISTING (`storage/api ↔ backend_resolver`), identical count on clean
  `main`; not introduced here.
