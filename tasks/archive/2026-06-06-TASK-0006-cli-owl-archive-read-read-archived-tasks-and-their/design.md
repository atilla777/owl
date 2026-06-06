---
status: approved
summary: Make `owl archive` a smart dispatcher (list/show/read subcommands + fallthrough archive verb), backed by a new read-only ArchiveReader internal module and Archive::Api read methods that resolve archived dirs by embedded TASK-ID through the archive storage role.
---

# Context

`owl archive` today is a single verb: `dispatch_command` routes `'archive'` →
`Internal::Commands::Archive.run`, which takes a TASK-ID positional and calls
`Owl::Archive::Api.archive_task`. Archived tasks land in `tasks/archive/<date>-<TASK-ID>-<slug>[-<suffix>]/`
containing `task.yaml` + artifact `.md` files (confirmed: TASK-0001's archive holds
`brief/design/plan/review/verification.md` + `task.yaml`).

No command reads them back. The archive storage role is a first-class role
(`config show` → roles include `archive`), so reads must go through that role, not hard-coded
`tasks/archive`.

# Decision

**1. Turn `archive` into a sub-dispatcher with backward-compatible fallthrough.**
In `dispatch_command`, `'archive'` → new `dispatch_archive(args, ...)`:
- if `args.first` ∈ `{'list','show','read'}` → route to the matching read command;
- else → `Internal::Commands::Archive.run` (the existing archive verb) unchanged.
Because task ids are `TASK-NNNN` and never equal a subcommand word, `owl archive TASK-0007`
still archives. Existing archive specs stay green.

**2. New read-only API surface** in `lib/owl/archive/`:
- `Owl::Archive::Api.list(root:)` → `Result.ok(archived: [{task_id, slug, archived_date, title, path}])`.
- `Owl::Archive::Api.show(root:, task_id:)` → `Result.ok(task_id, title, workflow_key, status, steps, artifacts:[{key, path}], path)` or `Result.err(:archived_task_not_found, available_ids:[...])`.
- `Owl::Archive::Api.read(root:, task_id:, artifact_key:)` → `Result.ok(task_id, artifact_key, path, body)` or `Result.err(:archived_artifact_not_found, available_keys:[...])`.
Implementation in `lib/owl/archive/internal/archive_reader.rb` (`module_function`), using
`Owl::Storage::Api` for role resolution + file reads (never `File.*` directly, per FS-access rule).

**3. Archive directory resolution.** Reader lists entries under the archive role dir, parses
each name as `^(?<date>\d{4}-\d{2}-\d{2})-(?<task_id>TASK-\d+)-(?<slug>.+)$`. `show`/`read`
match by `task_id`. On multiple matches (collision suffix), pick the lexicographically-last
directory (newest date sorts last) and include `path` so the caller sees which was chosen;
record the ambiguity is acceptable (documented), not an error.

**4. Artifact key discovery.** Source of truth = the archived `task.yaml` artifact map when
present; fall back to scanning `*.md` files in the dir (filename stem = key, excluding
`task.yaml`). This keeps `read` honest even if task.yaml lacks a full artifact map.

**5. Three thin CLI command modules** mirroring existing command style
(`ArchiveList`, `ArchiveShow`, `ArchiveRead` under `cli/internal/commands/`), each with
`--root`/`--json`, `JsonPrinter.success/failure`, and `TaskSupport` for root/error payloads.
`read` non-JSON mode prints the raw body to stdout.

# Alternatives

- **New top-level commands `archive-list/-show/-read`** — rejected: clutters the top-level
  namespace and reads worse than `archive <subcommand>`.
- **Un-archive-then-read** — rejected: mutates state for a read; defeats the purpose and risks
  collisions with live tasks.
- **Reuse `task inspect`/`artifact resolve` against archive paths** — rejected: those resolve
  through the `tasks`/live roles and the live index; archived tasks are intentionally out of the
  index, so a dedicated reader is cleaner than special-casing every live command.
- **Index archived tasks in `tasks/index.yaml`** — rejected for this task: larger change to the
  index contract; the directory scan is sufficient and keeps archive immutable.

# Risks

- **Dispatcher ambiguity** if a future subcommand name ever collided with a TASK-ID form —
  mitigated: TASK-ID regex (`TASK-\d+`) can never equal `list|show|read`; dispatcher checks the
  known-subcommand set explicitly.
- **Malformed archive dir names** (manually created) — reader skips entries that don't match the
  pattern rather than crashing; covered by a spec.
- **Collision suffixes** producing >1 dir for an id — deterministic newest-wins + `path` in
  output; documented.
- **FS-access rule**: all reads via `Owl::Storage::Api`; no raw `File`/`Dir` in API/internal
  beyond what storage exposes (follow `docs/agents/27_Owl_Ruby_code_architecture.md`).

# API

New public methods on `Owl::Archive::Api` (additive; `archive_task` unchanged):
- `list(root:) -> Result`
- `show(root:, task_id:) -> Result`
- `read(root:, task_id:, artifact_key:) -> Result`

New internal: `Owl::Archive::Internal::ArchiveReader.{list,show,read}`.

New CLI subcommands (additive; `owl archive TASK-ID` verb unchanged):
- `owl archive list [--root PATH] [--json]`
- `owl archive show TASK-ID [--root PATH] [--json]`
- `owl archive read TASK-ID ARTIFACT-KEY [--root PATH] [--json]`

New structured error codes: `archived_task_not_found` (with `available_ids`),
`archived_artifact_not_found` (with `available_keys`). JSON shapes as in the Decision section.
`lib/owl/archive/api.rb` is a public API file → its new methods need 100% line coverage.
