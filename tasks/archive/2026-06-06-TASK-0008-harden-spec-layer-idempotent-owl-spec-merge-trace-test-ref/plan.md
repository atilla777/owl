---
status: draft
summary: "Checklist to make owl spec merge idempotent (status skip + flip), add a TraceChecker under-root guard, and trace the previewed body on dry-run via Specs::Api.trace_body, with tests and 100% on specs/api.rb."
---

# Goal

Close the three spec-layer robustness gaps from the TASK-0007 review without changing happy-path
behaviour, with full tests and green gates.

# Checklist

1. **read_delta_meta** — in `lib/owl/specs/internal/task_merger.rb`, generalize `read_domain` to
   `read_delta_meta(delta_path)` returning `{domain:, status:}` (domain validated as today;
   `status` from front matter, default `nil`). Keep the same error results
   (`spec_delta_missing_domain`, `invalid_domain`).

2. **already_merged skip** — in `TaskMerger.merge`, after meta: if `status == 'merged'`, return
   `Result.ok(ok: true, applied: false, reason: 'already_merged', domain: meta.domain, merge: nil,
   trace: nil)` (write nothing).

3. **status flip after success** — in `apply_and_trace`, on a successful non-dry-run apply+trace,
   flip the delta front-matter `status` to `merged`: read the delta body, split front matter/body
   via `Owl::Validation::Internal::FrontMatterParser`, replace the `status:` value, re-serialize,
   `Storage::Api.write`. Dry-run must NOT flip. Return `reason: 'merged'` on a fresh apply (was
   nil). If the flip write fails, propagate the error (merge already persisted). Add a private
   `flip_delta_status(delta_path)` helper.

4. **trace_body** — add `Owl::Specs::Api.trace_body(root:, body:)` (public; keep api.rb 100%):
   `SpecDocument.parse(body)` → `TraceChecker.trace(model, root:)`, returning the standard trace
   report. Document it.

5. **dry-run traces preview** — in `apply_and_trace`, when `dry_run`, trace `applied.value[:after]`
   via `Specs::Api.trace_body(root:, body: after)` instead of `Specs::Api.trace(domain)`; non-dry-run
   keeps `trace(domain)` against the persisted spec. (Confirm `apply`'s result value key for the
   merged body is `:after`; adapt if named differently.)

6. **under-root guard** — in `lib/owl/specs/internal/trace_checker.rb` path-like branch: lexically
   normalize the root-joined ref (`Pathname#cleanpath`, no FS access) and require it to stay under
   the normalized project root; if it escapes → `dangling` (skip the `exists?`/traced path). In-root
   refs unchanged. Add a small `within_root?(root, ref)` helper. The only FS call stays
   `Storage::Api.exists?`.

7. **Tests** —
   - `spec/owl/specs/merge_task_idempotency_spec.rb`: re-run after success → `already_merged`,
     no `delta_conflict`; status flipped to `merged` after non-dry-run; dry-run does NOT flip;
     dry-run on a brand-new domain → traces preview, no `spec_not_found`, writes nothing.
   - `spec/owl/specs/internal/trace_checker_spec.rb`: `- TEST: ../outside.rb` → dangling (not
     traced); in-root existing ref → traced; in-root `a/../b_spec.rb` that stays inside → resolved
     normally; prose ref → unverified.
   - Extend `spec/owl/specs/merge_task_spec.rb` / api spec to cover `trace_body`.
   - Existing TASK-0007 merge/trace specs stay green.

8. **Gates** — `bundle exec rspec` green for touched areas + full-suite counts; `specs/api.rb` 100%
   via simplecov; `bundle exec rubocop` clean on changed files (never `-A`). If the suite dirties
   `README.md` (known pre-existing isolation bug), `git checkout README.md`. Clean up any throwaway
   `specs/<domain>` / tasks created while smoke-testing.

# Smoke test

```
# Seed a domain spec + a task spec_delta (status: draft, ADDED req w/ in-root TEST):
bin/owl spec merge TASK-XXXX --json            # ok, applied, reason: merged ; delta status -> merged
bin/owl spec merge TASK-XXXX --json            # ok, applied:false, reason: already_merged (idempotent)
# dry-run on a brand-new domain:
bin/owl spec merge TASK-YYYY --dry-run --json  # traces preview, no spec_not_found, no write
# traversal:
#   scenario with "- TEST: ../x.rb" -> owl spec trace <domain> --strict => dangling, ok:false
bundle exec rspec spec/owl/specs spec/owl/cli
bundle exec rubocop lib/owl/specs
# clean up throwaway specs/<domain>
```
