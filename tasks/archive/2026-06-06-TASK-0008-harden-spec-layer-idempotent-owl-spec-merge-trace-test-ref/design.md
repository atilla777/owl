---
status: approved
summary: "Idempotency via spec_delta status (skip already-merged; flip to merged after non-dry-run apply); a TraceChecker under-root guard so path refs escaping the project root are dangling; and dry-run tracing of the merge engine's previewed `after` body via a new Specs::Api.trace_body."
---

# Context

`TaskMerger.merge` (lib/owl/specs/internal/task_merger.rb) resolves the task's `spec_delta`,
reads its front-matter `domain` (`read_domain`), applies via `Specs::Api.apply` (P4), then gates
via `Specs::Api.trace(strict:true)` (P5). The `spec_delta` `status` field is currently ignored.
`MergeEngine` already serializes the merged `after` body and `apply`'s result value carries
`{before, after, unified_diff, created, ...}` — even under `dry_run` (it just does not persist).
`TraceChecker.classify_scenario` classifies a path-like `- TEST:` ref by `Storage::Api.exists?`
on a root-joined path, but does NOT verify the resolved path stays under the project root, so
`../outside.rb` is wrongly `traced`. `TraceChecker.trace(model, root:)` operates on an in-memory
parsed `SpecDocument` model — so tracing a previewed body needs no disk read.

# Decision

**1. Idempotent merge via `status`.**
- Extend `read_domain` (rename to `read_delta_meta`) to also return the front-matter `status`.
- In `merge`, after meta is read: if `status == 'merged'` → return
  `Result.ok(ok: true, applied: false, reason: 'already_merged', domain:, merge: nil, trace: nil)`
  and write nothing. (Operator re-drafts by setting `status: draft`.)
- After a SUCCESSFUL non-dry-run apply+trace, flip the delta's front matter `status` to `merged`:
  read the delta body, replace the `status:` value in the front matter (minimal, body preserved),
  write back via `Storage::Api.write`. Dry-run never flips. The flip is best-effort *after* the
  spec write; if the flip itself fails, surface it (the merge already happened). Keep the flip a
  small front-matter-only rewrite (reuse the FrontMatterParser to split front matter / body, swap
  the status line, re-serialize).
- `apply_and_trace` returns `reason: 'merged'` (was nil) on a fresh successful apply, so callers
  can distinguish fresh-merge from already-merged; `ok`/`applied`/`merge`/`trace` unchanged.

**2. Under-root traversal guard in TraceChecker.**
- Add a path-safety check in the path-like branch of `classify_scenario`: lexically normalize the
  root-joined ref (expand `.`/`..` WITHOUT touching the filesystem) and require it to stay within
  the normalized project root. If it escapes → classify as **dangling** (never traced), regardless
  of `exists?`. In-root existing refs stay traced; in-root missing refs stay dangling; non-path
  (prose) refs stay unverified. Use `Pathname#cleanpath` / lexical join for normalization (pure
  path math — allowed; it is not filesystem I/O, consistent with how other internals compute
  paths). The only FS call remains `Storage::Api.exists?`.

**3. Dry-run traces the previewed body.**
- Add `Owl::Specs::Api.trace_body(root:, body:)` → parse `body` with `SpecDocument.parse` and run
  `TraceChecker.trace(model, root:)`; returns the same shape as `trace` (no domain/disk read).
- In `TaskMerger.apply_and_trace`: when `dry_run`, trace `applied.value[:after]` via `trace_body`
  (the would-be-created/merged body) instead of `Specs::Api.trace(domain)`; when not dry-run, keep
  tracing the on-disk spec via `trace(domain)` (now persisted). This removes the `spec_not_found`
  preview error for a brand-new domain.

# Alternatives

- **Auto-flip status inside the P4 engine** — rejected: the engine merges spec bodies and knows
  nothing about the task's delta artifact; status is a task-merge concern, so it belongs in
  TaskMerger.
- **Make merge idempotent by diffing the spec instead of using status** — rejected: brittle
  (a MODIFIED/REMOVED delta has no simple "already applied" signal); the explicit `status` field
  is unambiguous and operator-controllable.
- **Resolve symlinks for the traversal guard (realpath)** — rejected: requires the path to exist
  and touches the FS; lexical normalization is sufficient to stop `..` escapes and keeps the check
  pure and deterministic.
- **Always trace the in-memory `after` body (even non-dry-run)** — rejected for non-dry-run: after
  a real write the on-disk spec is authoritative; tracing it exercises the real path.

# Risks

- **Status-flip corrupting the delta body** — mitigated: front-matter-only rewrite via
  FrontMatterParser split + re-validate the delta against the `spec_delta` type after the flip in
  tests; body bytes preserved.
- **Traversal normalization false-positives** on legit nested paths (`spec/owl/a/../b_spec.rb`) —
  mitigated: normalize THEN check the prefix is the root; a path that normalizes back under root is
  fine; tests cover an in-root `..` that stays inside.
- **Windows/edge path separators** — out of scope (project is POSIX); use Pathname lexical ops.
- **Dry-run body trace divergence** — the previewed `after` is exactly what a real apply would
  write (same serializer), so trace parity holds; covered by a dry-run-vs-real test.
- **api.rb coverage** — `trace_body` is a new public method on `Specs::Api`; exercise it (ok path)
  to keep `specs/api.rb` at 100%.

# API

New public: `Owl::Specs::Api.trace_body(root:, body:) -> Result`.
Changed internal: `TaskMerger` (status-aware skip + post-apply flip; dry-run uses trace_body),
`TraceChecker` (under-root guard). New `reason` values from `merge_task`: `already_merged`,
`merged` (fresh). No CLI signature change (`owl spec merge` / `owl spec trace` unchanged); their
JSON gains the new `reason` value and the traversal reclassification. `lib/owl/specs/api.rb`
requires 100% line coverage.
