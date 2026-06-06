---
status: approved
summary: "Harden the spec layer: make `owl spec merge` idempotent (status-aware skip + auto-flip to merged), classify out-of-root `- TEST:` refs as dangling instead of traced, and let `owl spec merge --dry-run` trace the previewed merged body for a brand-new domain."
---

# Problem

Three robustness gaps were surfaced by the TASK-0007 review of the spec-layer workflow
integration:

1. **`owl spec merge` is non-idempotent.** After a successful merge, re-running raises
   `delta_conflict` (the ADDED requirement now exists). Because `merge_docs` invokes
   `owl spec merge` and the orchestrator may legitimately re-run a step, a non-idempotent merge
   makes the wired step fragile.
2. **`- TEST:` path traversal.** `TraceChecker` marks a path-like ref `traced` whenever
   `Storage::Api.exists?` returns true — including refs like `../secret.rb` that resolve OUTSIDE
   the project root. Traceability should not be satisfiable by a path escaping the repo.
3. **`--dry-run` on a brand-new domain returns `spec_not_found`.** `merge --dry-run` traces the
   on-disk spec, which does not exist yet for a new domain, so the preview errors instead of
   tracing the would-be-created spec.

# Goal

Close the three gaps without changing the happy-path behaviour delivered in TASK-0007:

- `owl spec merge` becomes idempotent via the `spec_delta` `status` field.
- `- TEST:` refs that resolve outside the project root are classified as dangling (not traced).
- `owl spec merge --dry-run` traces the previewed merged body, so a new domain previews cleanly.

# Scenarios

### Requirement: Merge is idempotent via the spec_delta status

The system SHALL skip a spec_delta already marked merged and SHALL mark a delta merged after a
successful apply, so re-running `owl spec merge` does not error.

#### Scenario: Re-running a merged delta is a clean skip
- WHEN `owl spec merge TASK-ID` succeeds and is run a second time
- THEN the second run returns `{ok:true, applied:false, reason:"already_merged"}` and writes nothing
- AND it does NOT raise `delta_conflict`
- TEST: spec/owl/specs/merge_task_idempotency_spec.rb (re-run example)

#### Scenario: Successful apply flips the delta status
- WHEN a non-dry-run `owl spec merge TASK-ID` applies a delta
- THEN the task's `spec_delta.md` front matter `status` is updated to `merged`
- AND a dry-run does NOT change the status
- TEST: spec/owl/specs/merge_task_idempotency_spec.rb (status-flip example)

### Requirement: Out-of-root TEST references are not counted as traced

The trace checker SHALL classify a path-like `- TEST:` ref that resolves outside the project root
as dangling, never traced.

#### Scenario: Parent-escaping test ref
- WHEN a scenario carries `- TEST: ../outside.rb` (resolving outside the project root)
- THEN `owl spec trace <domain>` lists it under `dangling`, not as traced, and `--strict` is ok:false
- AND an in-root existing ref remains traced
- TEST: spec/owl/specs/internal/trace_checker_spec.rb (traversal example)

### Requirement: Dry-run previews a brand-new domain

The system SHALL trace the previewed merged body under `--dry-run` so a new domain does not error.

#### Scenario: Dry-run merge creating a new domain
- WHEN `owl spec merge TASK-ID --dry-run` targets a domain whose spec does not yet exist
- THEN the response traces the would-be-created merged body (no `spec_not_found`) and writes nothing
- TEST: spec/owl/specs/merge_task_idempotency_spec.rb (dry-run-new-domain example)

# Edge cases

- A spec_delta with `status: merged` from the start → first `owl spec merge` already skips
  (`already_merged`); document that an operator re-drafts by setting `status: draft`.
- Status flip must be a minimal front-matter edit that keeps the rest of the spec_delta body and
  its validation intact (re-validates against the `spec_delta` type after the flip).
- Traversal classification must use a normalized/expanded path comparison against the project root
  (handle `.`/`..`/symlink-free lexical normalization) and must NOT break legitimate in-root paths
  like `spec/owl/foo_spec.rb`.
- Non-path (prose/id) refs remain `unverified`, unaffected by the traversal guard.
- Dry-run must still write NOTHING (neither the spec nor the status flip).
- All FS access stays via `Owl::Storage::Api`; no raw File/Dir.

# Acceptance criteria

- [ ] `owl spec merge` skips an already-`merged` spec_delta (`reason:"already_merged"`) and flips a
      delta to `status: merged` on successful non-dry-run apply; dry-run never flips.
- [ ] `TraceChecker` classifies out-of-root path-like `- TEST:` refs as dangling; in-root and prose
      refs unchanged.
- [ ] `owl spec merge --dry-run` traces the previewed merged body (no `spec_not_found` for a new
      domain) and writes nothing.
- [ ] Logic stays in `Owl::Specs` (public api.rb → 100% line coverage), storage roles only.
- [ ] RSpec: idempotent re-run, status-flip (and dry-run no-flip), traversal dangling, in-root
      traced, dry-run-new-domain preview; existing TASK-0007 merge/trace specs stay green.
- [ ] `bundle exec rspec` green for touched areas; `bundle exec rubocop` clean (never `-A`).
