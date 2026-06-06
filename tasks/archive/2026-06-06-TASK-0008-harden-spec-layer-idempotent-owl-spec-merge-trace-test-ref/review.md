---
status: resolved
summary: "Adversarial self-review of the spec-layer hardening: idempotency, status-flip, traversal guard, dry-run preview, and trace_body all verified correct; two minor design caveats recorded, no blocker/major open. Gates green."
---

# Summary

Reviewed the TASK-0008 diff (`lib/owl/specs/api.rb`, `lib/owl/specs/internal/task_merger.rb`,
`lib/owl/specs/internal/trace_checker.rb`, the no_direct_fs allowlist edit, and the three spec
files). Hunted real bugs in the idempotency and path-normalization logic via hand-built `ruby -e`
probes and an end-to-end gate-fail probe. The implementation is correct on all happy-path and the
probed edge cases. Two minor design caveats are recorded for documentation; neither is a blocker.

Gates re-run: `rspec spec/owl/specs spec/owl/cli spec/owl/constitution` -> 418 examples, 0 failures.
`rubocop` on the 7 changed files -> no offenses. `lib/owl/specs/api.rb` at 100% line coverage
(absent from SimpleCov's below-100% report). README.md not dirtied; no throwaway `specs/<domain>`
left behind (probes ran under `/tmp` and were cleaned up).

# Findings

## Idempotency correctness — OK (no issue)
- The `status == 'merged'` skip happens in `TaskMerger.merge` BEFORE `apply_and_trace` is called,
  so `already_merged` writes nothing (no second apply, no `delta_conflict`). Confirmed by the new
  spec and a live probe: run1 `applied:true reason:merged`, run2 `applied:false
  reason:already_merged`, `merge:nil`.
- A delta that STARTS `status: merged` is skipped on the very first `merge` (`already_merged`). This
  matches the brief's documented edge case ("operator re-drafts by setting `status: draft`").
  Intended behaviour. Severity: none.

## Status-flip preserves the body verbatim; front-matter is semantically (not byte-for-byte) preserved — Minor
- The markdown body after the front matter is preserved verbatim (`parsed[:body]` is concatenated
  unchanged). Verified.
- The front matter is re-serialized via `YAML.dump`, which can reformat OTHER keys (e.g. double
  quotes -> single quotes, block-sequence indentation `  - a` -> `- a`) even though only `status`
  changes value. Key order is preserved (Ruby/Psych insertion order) and the result re-parses and
  re-validates cleanly against `spec_delta`, so this is purely cosmetic, not a correctness bug. The
  design called this a "minimal front-matter edit / swap the status line"; the implementation does
  a full re-dump instead. Severity: minor (nit). Resolution: left as-is.
- Dry-run does NOT flip and does NOT apply: the on-disk delta `status` stays `draft` after
  `--dry-run`, and no spec file is written. Confirmed by spec + probe.

## Traversal guard (path-normalization) — OK (no issue)
Probed `resolve_in_root` directly against the real repo root:
- `../outside.rb` -> nil -> dangling.
- in-root `spec/owl/specs/api_spec.rb` -> resolved -> traced.
- `a/../b_spec.rb` (normalizes back inside) -> resolved in-root.
- `foo/../../etc/passwd` (deep escape) -> nil -> dangling.
- ABSOLUTE `/etc/passwd` -> nil -> dangling. `Pathname#+` returns the absolute right operand, which
  fails the `start_with?("#{root}/")` prefix check, so absolute refs escaping root are safely
  dangling. (An absolute path that happens to be under root would be traced, which is acceptable.)
Normalization is purely lexical (`Pathname#cleanpath`, no realpath/FS); the only FS call remains
`Storage::Api.exists?` on the normalized path. The no_direct_fs allowlist gates `Pathname.new`; the
one-line addition of `specs/internal/trace_checker.rb` is justified (pure path-utility, category 3)
and minimal. Severity: none.

## trace_body — OK (no issue)
Robust on empty/`"\n\n"`/garbage/structure-only bodies (no crash; returns zeroed summary,
`valid:true`). Same return shape as `trace` minus domain/path. Covered by a new api spec; keeps
`specs/api.rb` at 100%. Severity: none.

## Dry-run preview on a new domain — OK (no issue)
Dry-run traces `applied.value[:after]` (the engine's serialized would-be body) via `trace_body`, so
a brand-new domain previews without `spec_not_found`, and writes nothing (asserted
`specs/payments/spec.md` absent). Confirmed by spec. Severity: none.

## Gate-fail flips status to merged — Minor (deliberate design caveat, surfaced)
`Specs::Api.trace(strict: true)` returns `Result.ok(ok: false, ...)` on a coverage failure — it is
NOT an `err?` result. So in `apply_and_trace` the early `return traced if traced.err?` does NOT
trigger on a gate-fail, and the non-dry-run `flip_delta_status` runs unconditionally. Live probe
(delta with a dangling `- TEST: ../escape.rb`): run1 `ok:false applied:true reason:merged`, delta
status flipped to `merged`; run2 `ok:true applied:false reason:already_merged`.

Verdict: this is deliberate and defensible. `apply` already persisted the merged spec regardless of
the trace verdict (documented: "a trace gate failure ... does NOT roll back the applied delta"), so
NOT flipping would make a re-run raise `delta_conflict` — strictly worse. Flipping makes the re-run
a clean `already_merged` skip. The coherent caveat is that a gate-failed merge becomes `ok:true` on
re-run (the `already_merged` path is unconditionally `ok:true`), so the transient `ok:false`
coverage signal is "forgotten." Consumers (e.g. `merge_docs`) should therefore treat
`owl spec trace --strict` as the authoritative coverage gate, not a re-run of `merge_task`.
Severity: minor — behaviour is correct for idempotency; only the doc comment on `merge_task` could
note that the delta is flipped to `merged` even on a gate-fail. No code change required.

## Regressions — OK
TASK-0007 merge/trace specs and the P4/P5 specs are green within the 418-example run.

# Resolution

- Idempotency / skip-before-apply: verified correct. No change. (no severity)
- Status-flip body preservation: body verbatim; front matter semantically preserved but YAML-
  reformatted. Minor/nit, left as-is — re-parses and re-validates cleanly. (minor, accepted)
- Dry-run no-flip / no-write: verified. No change. (no severity)
- Traversal guard incl. absolute-path and deep-escape: verified safe and lexical. Allowlist edit
  justified and minimal. No change. (no severity)
- trace_body robustness + coverage: verified; `specs/api.rb` 100%. No change. (no severity)
- Dry-run new-domain preview: verified. No change. (no severity)
- Gate-fail status flip: deliberate and correct for idempotency; documentation caveat surfaced
  (optional doc note on `merge_task`). No code change. (minor, accepted)

No blocker or major findings remain open, so `status: resolved`. No in-line fixes were required —
the diff was correct on every probed path.
