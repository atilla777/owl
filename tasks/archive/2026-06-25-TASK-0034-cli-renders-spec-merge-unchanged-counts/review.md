---
status: resolved
verdict: accepted
summary: "Independent review of TASK-0034 — surfacing the spec-merge `unchanged` (no-op) counts that the TASK-0029 engine already computed but the CLI hid. The data is genuine: the engine's `DeltaMerger` returns `unchanged: {added,modified,removed}` (delta_merger.rb:44-45), `MergeEngine.summarize` carries it through (merge_engine.rb:85) and crucially subtracts it from `applied` (counts(), lines 132-134) — so `applied` is the truly-changed count and `unchanged` the no-op count; the two are never confused. `Specs::Api.apply`/`diff` already passed `unchanged` (api.rb:131,158), so `spec_apply#emit` adding `unchanged: value[:unchanged]` is a direct, correct passthrough. For merge, `value.dig(:merge,:unchanged)` reads the same hash via the nested `merge:` payload. nil-safety holds on both no-op paths: `skipped` (no_spec_delta) and `already_merged` set `merge: nil`, so `dig` yields nil → JSON `unchanged: null` (verified live), and `--no-json` `print_unchanged`/`print_merge`/`print_trace` all guard on `merge.is_a?(Hash)` so the already_merged fall-through prints no line and never crashes; no_spec_delta returns early before print_unchanged. Idempotency is now visible and the test proves it (apply twice: applied {added:1}→{added:0}, unchanged {0}→{added:1}) — reproduced live. Engine untouched (`git diff --stat lib/owl/specs/` empty); additive field is back-compat. Full suite 1973 examples / 0 failures / 1 pre-existing pending, exit 0; rubocop clean on all 4 touched files; README not dirtied. patch 0.17.1→0.17.2 + CHANGELOG correct for additive output. Verdict: accepted."
---

# Summary

Independent, adversarial review of TASK-0034 — the completion of the TASK-0029
honest-counts work. The spec-merge engine already counted idempotent no-ops as
`unchanged: { added, modified, removed }`, but the CLI never exposed them. The
change is purely presentational: it surfaces that pre-existing engine value in
three places (`owl spec apply --json`, `owl spec merge --json` top level, and
`owl spec merge --no-json` summary), with no engine edit.

I re-derived every focus point from the diff, the specs engine (`api.rb`,
`merge_engine.rb`, `delta_merger.rb`, `task_merger.rb`), confirmed the engine is
untouched, ran the full suite + RuboCop, and did a live smoke of both the
idempotent apply path and all three merge no-op paths. No defects found.
Verdict: **accepted**.

Production changes reviewed:
- `lib/owl/cli/internal/commands/spec_apply.rb` — `emit` JSON payload gains
  `unchanged: value[:unchanged]` (direct passthrough of the value `Specs::Api.apply`
  already returns).
- `lib/owl/cli/internal/commands/spec_merge.rb` — `json_payload` gains
  `unchanged: value.dig(:merge, :unchanged)` at the top level; new
  `print_unchanged` prints `  unchanged: added … modified … removed …` after the
  `delta:` line in `--no-json`, gated on `merge.is_a?(Hash)`.
- `lib/owl/version.rb` 0.17.1→0.17.2, `CHANGELOG.md` `[0.17.2]`.
- Specs: `spec_apply_diff_command_spec.rb` (+ idempotent re-apply test, + one
  assertion), `spec_merge_command_spec.rb` (+ two assertions).

# Findings

All five review-focus points checked against code, the engine, the test run, and
a live smoke. Each confirmed.

1. **Data correctness — OK.** `value[:unchanged]` for apply originates in
   `DeltaMerger.apply`, which builds `unchanged = { added:, modified:, removed: }`
   (delta_merger.rb:44-45) from per-operation no-op tallies (`+= 1` only when a
   requirement is re-set/re-removed/re-added with identical content, lines
   58/71/85). `MergeEngine.summarize` returns it as `unchanged:` (merge_engine.rb:85),
   and `Specs::Api.apply`/`applied_result` (api.rb:158) and `diff` (api.rb:131)
   pass it through unchanged — so `spec_apply#emit`'s `unchanged: value[:unchanged]`
   is exact. For merge, `merged_result` nests the apply payload under `merge:`
   (task_merger.rb:98), so `value.dig(:merge, :unchanged)` reads the same hash.
   Counters are **not** swapped with `applied`: `counts()` defines
   `applied = ops.length − unchanged` (merge_engine.rb:132-134), i.e. applied is
   the genuinely-changed count and unchanged the no-op count — orthogonal, never
   double-counted. Shape `{added,modified,removed}` confirmed end-to-end.

2. **nil-safety / no-op — OK.** Both graceful no-op merge paths set `merge: nil`:
   `skipped` (`reason: no_spec_delta`, task_merger.rb:184) and `already_merged`
   (task_merger.rb:188). So `value.dig(:merge, :unchanged)` yields `nil` → JSON
   `unchanged: null` (verified live). In `--no-json`, `no_spec_delta` returns
   early in `emit_summary` (line 62-65) before `print_unchanged` ever runs;
   `already_merged` falls through but `print_merge`/`print_unchanged`/`print_trace`
   each guard on `merge.is_a?(Hash)` and return on `nil` — so the re-run prints
   only the `(applied: false)` header with no unchanged line and no crash
   (reproduced live). The pre-existing `no_spec_delta` JSON test still passes.

3. **Idempotency visible — OK, test is genuine.** The new
   spec_apply_diff_command_spec test runs the identical `spec apply … --json`
   argv twice against the same project: the first apply, then a re-apply, and
   asserts `applied == {added:0,modified:0,removed:0}` AND
   `unchanged == {added:1,modified:0,removed:0}`. That is a real second
   invocation through the full CLI (not a stub), so it genuinely proves the
   no-op is now visible. Reproduced live in a throwaway project: apply #1 →
   `applied {added:1}, unchanged {0}`; apply #2 → `applied {0}, unchanged {added:1}`.

4. **Additivity / back-compat — OK.** `git diff --stat lib/owl/specs/` is empty:
   the engine is untouched, so merge/apply semantics are unchanged. The new
   `unchanged` keys are pure additions to existing JSON payloads (no field
   renamed/removed) and the new `--no-json` line is appended — existing consumers
   reading `ok`/`applied`/`reason`/`domain`/`merge`/`trace` are unaffected. The
   merge JSON keeps the nested `merge.unchanged` and now also hoists it to the
   top level, consistent with how `applied` is mirrored.

5. **Version + CHANGELOG — OK.** patch 0.17.1→0.17.2 is right: additive output
   with no behavior, on-disk-format, or contract removal is a back-compat add,
   i.e. patch per the project SemVer rule. The `[0.17.2]` entry accurately
   describes the three surfaces and states the engine is unchanged and that a
   `no_spec_delta` no-op prints no unchanged line. Coverage gate untouched: the
   edits are in CLI command modules, not `**/api.rb` files (`Specs::Api` was not
   modified), so the public-API line-coverage gate is unaffected.

# Resolution

Accepted. The change does exactly what the brief describes — it surfaces the
engine's pre-existing `unchanged` no-op counts in `owl spec apply --json`,
`owl spec merge --json`, and `owl spec merge --no-json`, with correct nil-safety
on both no-op merge paths and an honest idempotency test. The engine is provably
untouched, the field additions are back-compat, and the full suite + RuboCop are
green. No changes required.

# Remediation

n/a — no defects found.

# Residual risks

- The merge JSON now carries `unchanged` both at the top level and nested under
  `merge.unchanged` (intentional mirror of `applied`); a consumer must not treat
  them as independent — they are the same hash. Documented in CHANGELOG.
- For top-level `unchanged` on a no-op merge the value is `null` (not a zeroed
  hash), unlike a real merge which returns `{added:0,…}`. Consumers should
  null-check, which the early-return / `dig` design makes explicit and is the
  same nil-shape the existing `merge`/`trace` keys already use on no-op.
