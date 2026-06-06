---
status: passed
summary: "Spec-layer hardening implemented: idempotent owl spec merge (already_merged skip + status flip, dry-run no-flip), dry-run new-domain preview via Specs::Api.trace_body, and TraceChecker under-root traversal guard. Full RSpec green (0 failures); specs/api.rb at 100%; RuboCop clean on changed files."
---

# Summary

All three robustness gaps from the TASK-0007 review are closed without changing happy-path
behaviour:

1. `owl spec merge` is idempotent. `TaskMerger.read_domain` was generalized to `read_delta_meta`
   returning `{domain:, status:}`. A delta already `status: merged` returns
   `{ok:true, applied:false, reason:'already_merged', domain:, merge:nil, trace:nil}` and writes
   nothing. A successful non-dry-run apply flips the delta front-matter `status` to `merged` via the
   new private `flip_delta_status` helper (FrontMatterParser split + YAML re-serialize, body
   preserved); a fresh apply now returns `reason: 'merged'`. Dry-run never flips.
2. Dry-run traces the previewed body. New public `Owl::Specs::Api.trace_body(root:, body:)` parses
   the body and runs `TraceChecker.trace`. `TaskMerger.apply_and_trace` (via `trace_merge`) traces
   `applied.value[:after]` (the merge engine's serialized merged body) under dry-run, and the
   persisted on-disk spec via `trace(domain)` otherwise — removing the `spec_not_found` dry-run
   error for a brand-new domain.
3. Under-root traversal guard. `TraceChecker#resolve_in_root` lexically normalizes the root-joined
   ref (`Pathname#cleanpath`, no FS access) and returns the normalized in-root path or `nil` when
   the ref escapes the project root; an escaping path-like `- TEST:` ref is classified `dangling`
   (never traced). The only FS call remains `Owl::Storage::Api.exists?` (now on the normalized
   path). `specs/internal/trace_checker.rb` was added to the constitution no-direct-FS allowlist as
   a pure path-utility (cleanpath is lexical math, not I/O).

# Commands

- `bundle exec rspec spec/owl/specs` -> 91 examples, 0 failures.
- `bundle exec rspec` (full suite) -> 1403 examples, 0 failures, 1 pending. Exit code 1 comes ONLY
  from the pre-existing `lib/owl/steps/api.rb` 99.16% coverage gate (unrelated to this task).
- `bundle exec rspec spec/owl/specs spec/owl/constitution/no_direct_fs_spec.rb` -> 93 examples,
  0 failures.
- `bundle exec rubocop` on the 7 changed files -> no offenses detected.

# Outcomes

- `lib/owl/specs/api.rb` line coverage: 100% (not listed under SimpleCov's below-100% report).
- Full-suite SimpleCov below-100% report lists ONLY `lib/owl/steps/api.rb: 99.16%` — the known
  pre-existing gap.
- Idempotency tests pass: re-run -> `already_merged` (no `delta_conflict`); status flipped to
  `merged` after non-dry-run; dry-run does NOT flip.
- Dry-run-new-domain preview test passes: traces the previewed body (no `spec_not_found`), writes
  nothing (asserted `specs/payments/spec.md` absent).
- Traversal tests pass: `- TEST: ../outside.rb` -> dangling; in-root existing ref -> traced;
  in-root `a/../present_spec.rb` normalizing back inside -> traced; prose ref -> unverified.
- Existing TASK-0007 merge/trace specs stay green.
- README.md was NOT dirtied by this run; no throwaway `specs/<domain>` dirs were left behind; no
  cleanup needed.

## Files changed

- `lib/owl/specs/internal/task_merger.rb`
- `lib/owl/specs/api.rb`
- `lib/owl/specs/internal/trace_checker.rb`
- `spec/owl/constitution/no_direct_fs_spec.rb`
- `spec/owl/specs/api_spec.rb` (trace_body)
- `spec/owl/specs/internal/trace_checker_spec.rb` (traversal cases)
- `spec/owl/specs/merge_task_idempotency_spec.rb` (new)
