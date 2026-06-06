---
status: draft
summary: Ordered checklist to add owl archive list/show/read read-only CLI backed by an ArchiveReader, with backward-compatible archive-verb dispatch and full specs.
---

# Goal

Ship `owl archive list|show|read` as read-only commands backed by `Owl::Archive::Api`
read methods + an `ArchiveReader` internal, keeping `owl archive TASK-ID` archiving unchanged,
with full RSpec coverage and 100% coverage on `archive/api.rb`.

# Checklist

1. **ArchiveReader internal** — add `lib/owl/archive/internal/archive_reader.rb`
   (`module_function`). Resolve the archive role base dir via `Owl::Storage::Api`. Implement:
   - `list(root:)` → scan base dir entries, parse `^(\d{4}-\d{2}-\d{2})-(TASK-\d+)-(.+)$`; skip
     non-matching; for each read `task.yaml` (via storage) for `title`; return ordered
     `[{task_id, slug, archived_date, title, path}]` sorted by dir name.
   - `find_dir(root:, task_id:)` helper → newest matching dir or nil.
   - `show(root:, task_id:)` → from the dir: parse `task.yaml`, build
     `{task_id, title, workflow_key, status, steps, artifacts:[{key,path}], path}`. Artifact keys
     from task.yaml artifact map if present, else `*.md` stems (excluding none special). Err
     `archived_task_not_found` with `available_ids` when no dir.
   - `read(root:, task_id:, artifact_key:)` → resolve `<dir>/<key>.md` (or path from task.yaml
     artifact map); return `{task_id, artifact_key, path, body}`; err
     `archived_artifact_not_found` with `available_keys` when absent.

2. **Archive::Api read methods** — in `lib/owl/archive/api.rb` add `list/show/read` delegating to
   `ArchiveReader`. Keep `archive_task` as-is. (Public API file → 100% line coverage required.)

3. **CLI: ArchiveList** — `lib/owl/cli/internal/commands/archive_list.rb`: `--root/--json`,
   resolve root via `TaskSupport`, call `Api.list`, `JsonPrinter.success(ok:true, archived:[...])`.

4. **CLI: ArchiveShow** — `lib/owl/cli/internal/commands/archive_show.rb`: positional TASK-ID
   (required → `invalid_arguments`), call `Api.show`, success payload or
   `TaskSupport.error_payload` on err.

5. **CLI: ArchiveRead** — `lib/owl/cli/internal/commands/archive_read.rb`: positionals
   TASK-ID + ARTIFACT-KEY (both required), call `Api.read`; JSON → `{ok, task_id, artifact_key,
   path, body}`; non-JSON → print raw `body` to stdout.

6. **Dispatcher** — in `lib/owl/cli/api.rb`: add `require_relative` for the three new commands;
   change `when 'archive'` to call new `dispatch_archive(args, **kwargs)`:
   `case args.first; when 'list' (shift) ArchiveList; when 'show' (shift) ArchiveShow;
   when 'read' (shift) ArchiveRead; else Archive.run(argv: args, ...)` (verb fallthrough).
   Update `HELP_TEXT` to document the three read subcommands.

7. **Specs — API** — `spec/owl/archive/api_spec.rb` (create or extend): seed a project, create +
   archive a task with artifacts, then assert `list` (populated + empty), `show` (fields +
   unknown id err + available_ids), `read` (body + missing key err + available_keys). Drive via
   `Owl::Archive::Api` and/or `Owl::Cli::Api.run` end-to-end.

8. **Specs — CLI dispatch** — `spec/owl/cli/...`: assert `owl archive list/show/read` route
   correctly AND `owl archive TASK-ID` still archives (backward-compat). Cover non-JSON `read`
   raw-body output and `invalid_arguments` on missing positionals.

9. **Specs — ArchiveReader unit** — `spec/owl/archive/internal/archive_reader_spec.rb`: malformed
   dir names skipped, collision-suffix newest-wins, artifact-key discovery from task.yaml vs
   filename fallback.

10. **Coverage** — ensure `lib/owl/archive/api.rb` hits 100% line coverage (every new method
    exercised, both ok and err branches via the API path).

11. **Gates** — `bundle exec rspec` green; `bundle exec rubocop` clean on changed files (never
    `-A`).

# Smoke test

```
# An already-archived task exists (TASK-0001). Exercise the new surface:
bundle exec owl archive list --json                 # -> archived:[{task_id:"TASK-0001",...}]
bundle exec owl archive show TASK-0001 --json       # -> steps + artifacts:[{key:"review",...}]
bundle exec owl archive read TASK-0001 review --json # -> body contains the P3 review findings
bundle exec owl archive read TASK-0001 nope --json   # -> archived_artifact_not_found + available_keys
bundle exec owl archive show TASK-9999 --json        # -> archived_task_not_found + available_ids

# Backward compat (do NOT actually archive in smoke unless on a throwaway task):
bundle exec rspec spec/owl/archive spec/owl/cli
bundle exec rubocop lib/owl/archive lib/owl/cli/api.rb lib/owl/cli/internal/commands/archive_*.rb
```
