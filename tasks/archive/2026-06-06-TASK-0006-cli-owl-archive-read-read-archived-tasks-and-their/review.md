---
status: resolved
summary: Adversarial self-review of the read-only `owl archive list|show|read` surface. No blocker/major findings; backward-compat archive verb, read-only guarantee, FS-access rule, structured errors, and every design edge case are genuinely spec-covered. archive/api.rb at 100% line coverage, rubocop clean, no_direct_fs meta-spec passes. Four minor/nit notes recorded, none requiring a code change.
---

# Summary

The change adds a read-only archive surface (`owl archive list|show|read`) backed by
`Owl::Archive::Api.{list,show,read}` delegating to a new
`Owl::Archive::Internal::ArchiveReader`, plus a `children(path:)` enumerator on the storage
facade/backend and a `dispatch_archive` sub-dispatcher in `lib/owl/cli/api.rb`. I reviewed the
full diff against brief + design + plan, re-ran the gates, and probed each risk the prompt
called out. The implementation matches the design decisions, is genuinely read-only, and the
backward-compatible archive verb is preserved. No blocker or major issues found.

Verified gates (actual numbers):
- `bundle exec rspec spec/owl/archive spec/owl/cli spec/owl/storage`: 372 examples, 0 failures,
  1 pending (pre-existing SQLite concurrent-write contract, unrelated).
- `bundle exec rubocop` on all 8 changed lib files + 3 new CLI commands + archive specs (15
  files): no offenses detected. No `-A` used.
- `spec/owl/constitution/no_direct_fs_spec.rb`: 2 examples, 0 failures.
- `lib/owl/archive/api.rb`: 100% line coverage (absent from the simplecov "below 100%" list;
  every method exercised ok + err via the API path in `spec/owl/archive/api_spec.rb`).

# Findings

### 1. Backward compatibility of the archive verb — PASS (no finding)
- Severity: n/a. `dispatch_archive` checks `args.first` against the literal set `{list,show,read}`
  and otherwise calls `Internal::Commands::Archive.run(argv: args, **)` with the TASK-ID still in
  `args.first` (not dropped). Task ids are `TASK-\d+` and can never equal a subcommand word, so no
  mis-parse is possible. Proven by `spec/owl/cli/archive_read_command_spec.rb` "still archives a
  live task when the arg is a TASK-ID (backward compatible)" which asserts the live dir is removed
  and the existing archive payload (`to` under `tasks/archive/`) is returned. Existing
  `spec/owl/cli/archive_command_spec.rb` + `spec/owl/archive/*` archive-verb specs stay green.

### 2. Read-only guarantee — PASS (no finding)
- Severity: n/a. The reader only calls `Owl::Storage::Api.resolve/children/read` and YAML.safe_load;
  no write/move/delete anywhere. The new storage `children(path:)` is a pure enumerator
  (`Pathname#children`, returns `[]` for non-directories) with no mutation. All three CLI commands
  only print.

### 3. FS-access rule / no_direct_fs meta-spec — PASS (minor note)
- Severity: minor (note only, no change). No `File.`/`Dir.`/`FileUtils.`/`Pathname.new` in any new
  archive lib file, so the syntactic `no_direct_fs` meta-spec passes and `archive_reader.rb` does
  not need an allowlist entry. Caveat for the spirit of the rule: `ArchiveReader` calls
  `.directory?`, `.file?`, `.extname`, `.basename`, `.children` on the `Pathname` objects that
  `Owl::Storage::Api.children` returns; `.directory?`/`.file?` perform `stat` I/O. This is inside
  the abstraction's intent (the handles came from the storage layer) and the constitution gate is
  syntactic, so it is acceptable; recorded only because storage hands out raw FS-capable Pathnames.
- Resolution: accepted as-is. The funnel is through `Owl::Storage::Api` and the meta-spec passes.

### 4. Collision newest-wins is lexicographic, not numeric — minor
- Severity: minor. `find_dir` resolves collisions with `max_by { |e| e[:dir].basename.to_s }`
  (lexicographic on the whole dir name). Collision suffixes are numeric 2..100
  (`destination_planner.rb`). For ≥10 same-date + same-id + same-slug archives, lexicographic order
  diverges from numeric (`-slug-99` sorts above `-slug-100`), so "newest" could resolve to the
  wrong dir.
- Resolution: not fixed, and not a defect against spec. The design explicitly chose
  "lexicographically-last directory (newest date sorts last)", and the dominant determinism — newest
  by ISO date prefix — is correct (YYYY-MM-DD sorts chronologically). The double-digit edge is
  practically unreachable: a TASK-ID is archived exactly once in normal operation (the live dir is
  removed and ids are not reused), so >9 same-id+same-date+same-slug collisions cannot occur.
  Changing it would deviate from the documented decision and add suffix-parsing for an unreachable
  case. Covered (single-digit) by reader spec "resolves the newest directory when collision
  suffixes produce multiple matches".

### 5. `read --no-json` still emits JSON on error — nit
- Severity: nit. In `archive_read.rb` the err check (`JsonPrinter.failure` → JSON on stderr) runs
  before the `--no-json` raw-body branch, so `archive read ID badkey --no-json` prints a JSON error
  to stderr rather than nothing/plain text.
- Resolution: accepted. Structured JSON errors on stderr is the consistent convention across the CLI;
  the raw-body mode is only meaningful on success. No change.

### 6. `entries(...).value` assumes children never errs — nit
- Severity: nit. `ArchiveReader#entries` calls `Owl::Storage::Api.children(path:).value` without an
  err guard. Safe today: the filesystem backend wraps `children` unconditionally in `Result.ok`.
- Resolution: accepted; brittle only if a future backend returns an err from `children`. No change.

# Resolution

All design edge cases are genuinely spec-covered (not merely claimed): malformed dir names skipped,
collision newest-wins, artifact-key discovery from the `task.yaml` artifact map vs `*.md` filename
fallback, `archived_task_not_found`/`archived_artifact_not_found` carrying `available_ids`/
`available_keys`, `invalid_arguments` on missing positionals, and non-JSON raw-body output — see
`spec/owl/archive/internal/archive_reader_spec.rb`, `spec/owl/archive/api_spec.rb`, and
`spec/owl/cli/archive_read_command_spec.rb`. `lib/owl/archive/api.rb` is at 100% line coverage,
rubocop is clean on all changed files, and the `no_direct_fs` constitution meta-spec passes.

No code changes were required. Findings 3–6 are minor/nit and explicitly accepted with rationale;
none is a blocker or major. `status: resolved`.
