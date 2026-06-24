---
status: resolved
summary: "P1-B cross-task dependencies (blocked_by DAG) + owl task ready reviewed against design: canonical blocked_by, computed blocks, behavior-preserving CycleDetector extraction, dep-aware ready, dangling-ref cleanup. All checks green; no defects."
verdict: accepted
ready: true
---

# Summary

Reviewed the TASK-0026 implementation of cross-task dependencies (`blocked_by`
DAG) and the dependency-aware `owl task ready` command against the approved
`design` artifact. The change matches the design exactly: `blocked_by` is the
sole stored edge, `blocks`/dependents are computed by reverse index scan, cycle
detection is shared between workflow-step validation and task-dep validation via
an extracted `Owl::Internal::CycleDetector`, and the orchestrator scope boundary
(`available`/`next`/auto-claim stay dep-blind) is honoured.

Objective gate: full suite green (1891 examples, 0 failures, 1 pre-existing
pending), SimpleCov 100% line-coverage gate on `lib/owl/**/api.rb` green (rspec
exit 0), RuboCop net-zero on all 15 changed/new files, README reverted. No
defects found.

# Findings

Scrutiny focused on the regression-prone items called out in the step brief.

1. **CycleDetector extraction is behavior-preserving (no workflow regression).**
   `graph_builder.rb` now projects `nodes.transform_values { |n| n[:requires] }`
   into an adjacency map and delegates to `Owl::Internal::CycleDetector.detect`.
   The DFS three-colour walk and the cycle-path shape
   (`stack[stack.index(neighbor)..] + [neighbor]`, first == last) are identical
   to the original private `visit_for_cycle`. `detect_cycle` is kept as a thin
   named wrapper so existing callers/tests keep their entrypoint. Verified:
   `spec/owl/workflows/graph_builder_spec.rb` 14/14 pass, including "returns
   :workflow_cycle with the cycle path" — the `workflow_cycle` error code and
   path are still produced. The only semantic shift is that a dangling neighbor
   (a `requires`/`blocked_by` id that is not itself a key) is now tolerated as a
   leaf instead of raising `NoMethodError`; this is strictly more robust and
   exercised by `cycle_detector_spec` ("tolerates neighbors that are not keys").
   Severity: none (improvement).

2. **CycleDetector finds direct and transitive cycles.** `cycle_detector_spec`
   covers direct (`a->b->a`), transitive (multi-hop), and self-loop (`a->a`,
   returns `%w[a a]`) cases. `api_dependencies_spec` confirms `dep add` rejects
   both direct and transitive cycles with `:dependency_cycle` and a path whose
   first element equals its last. Severity: none.

3. **`dep add` validations correct.** Self-dep → `:self_dependency` (checked
   before any FS read); unknown TASK or unknown DEP → `:task_not_found` (both
   endpoints read via `TaskReader` in `read_pair`); cycle → `:dependency_cycle`
   carrying the path. Re-adding an existing edge is a clean ok no-op that skips
   the cycle check (`blocked_by.include?(depends_on)` early return). `dep rm` of
   an absent edge is a clean no-op. `dep list` returns `{blocked_by, blocks}`
   with `blocks` computed by reverse-scanning the index. Severity: none.

4. **`owl task ready` correctness.** `ReadyScanner#ready_entry?` excludes own
   terminal status (`done`/`archived`/`abandoned`), requires every `blocked_by`
   dep complete, and excludes tasks with a live (non-expired) claim lease.
   `deps_complete?` treats a dep whose status is `nil` (missing/archived out of
   the index) OR in `{done, archived}` as satisfied — so a dangling or archived
   dependency counts as complete and never blocks forever or crashes. Sorted by
   priority desc, then `created_at`, then id. Specs confirm: blocked while dep
   unfinished, unblocked once dep `done`, archived dep complete, missing dep
   (`TASK-9999`) complete + `be_ok` no-crash, and a claimed task excluded.
   Severity: none.

5. **Dangling refs cleaned on delete.** `deleter.rb#clean_dangling_refs` runs
   before the index rebuild and strips the deleted id from every other live
   task's `blocked_by` via `AtomicYamlWriter`, guarded by `IdGenerator.parse`
   and rescuing `Psych::SyntaxError`. Spec confirms post-delete `blocked_by` and
   index entry are `[]` and `ready` stays `be_ok`. The preferred cleanup path
   from the design is implemented, and `ready`/cycle paths are independently
   resilient to dangling refs as defense-in-depth. Severity: none.

6. **All index writes go through the locked `IndexWriter`.** Grep confirms
   `dependency_writer.rb` and `deleter.rb` mutate only individual `task.yaml`
   files via `AtomicYamlWriter` and recompute `tasks/index.yaml` exclusively
   through `IndexWriter.rebuild`. No bypass of the lock. Severity: none.

7. **Scope boundary honoured.** The diff touches no `availability_scanner`,
   `owl next`, or auto-claim code; `ready` is an additive new command. The
   deferred orchestrator dep-awareness follow-up is correctly left untouched.
   Severity: none.

8. **Coverage + version.** Coverage gate green: new branches in `tasks/api.rb`
   (4 thin delegators) and `cli/api.rb` (`dispatch_task_dep` + `ready`
   registration) are all covered (rspec exit 0; no api.rb below 100%).
   `Owl::VERSION` 0.12.0 → 0.13.0 (MINOR — additive feature) with a matching
   `CHANGELOG.md` [0.13.0] entry. Schema `blocked_by` is optional, legacy reads
   as `[]`, `additionalProperties` preserved. Severity: none.

# Resolution

No findings required code changes. The implementation matches the approved
`brief`, `design`, and `plan`. Verdict: **accepted**. The two design-flagged
follow-ups (orchestrator dep-awareness; per-`task.yaml` mutation lock) are
explicitly out of scope and are not defects.

# Remediation

None required.

# Residual risks

- **Concurrent edits to the same `task.yaml`.** `dep add/rm` and the delete
  dangling-ref scrub rewrite a single task.yaml atomically (per-file) and then
  rebuild the index under the lock — consistent with existing
  `StatusWriter`/`LabelWriter`. Two sessions editing the *same* task's
  `blocked_by` concurrently are not serialized. Pre-existing project-wide
  pattern; deferred follow-up, not introduced here.
- **Cycle check cost.** Built per-write over the index adjacency (O(V+E)); cheap
  at current scale, documented in the design.
