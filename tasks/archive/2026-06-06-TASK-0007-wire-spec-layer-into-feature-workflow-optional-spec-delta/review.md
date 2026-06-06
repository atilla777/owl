---
status: resolved
summary: "Adversarial self-review of TASK-0007 (wire spec engines into feature workflow): backward-compat guarantee, gate semantics, dry-run, and error propagation all verified by live probes; no blocker/major findings; 3 minor by-design notes recorded."
---

# Summary

Reviewed the TASK-0007 diff: new `spec_delta` artifact type (active +
seed + registered in `.owl/artifacts.yaml` and `default_template.rb`),
optional `spec_delta` declaration in the `feature` workflow (active +
seed), `Owl::Specs::Internal::TaskMerger`, `Owl::Specs::Api.merge_task`,
the `owl spec merge` CLI, and the updated `merge_docs.context.md` (active
+ seed).

The central guarantee holds: a task with no `spec_delta` is a clean
no-op. Declaring an OPTIONAL `spec_delta` in the feature workflow does
not change the step graph, task creation, ready-steps, status, or
archive behaviour. All five P2 design scenarios and the documented edge
cases were verified by live CLI probes, not just by reading the diff or
trusting the verification report.

Gates re-run (actual numbers):
- `bundle exec rspec spec/owl/specs spec/owl/cli spec/owl/integration spec/owl/artifacts spec/owl/workflows spec/owl/constitution` → 701 examples, 0 failures.
- `bundle exec rubocop` on the 10 changed/added lib + spec files → no offenses (never `-A`).
- `lib/owl/specs/api.rb` → 100% line coverage (not listed in the SimpleCov "below 100%" report).
- `bin/owl artifact-type validate spec_delta` → `valid: true`.
- `bin/owl workflow validate feature` → `valid: true`.
- README.md NOT dirtied this run.

# Findings

## Backward-compat guarantee (central) — VERIFIED, no issue

Created a fresh task `TASK-0008` (allocator correctly skipped to 0008,
not 0001). Observed:
- Step graph unchanged: brief→design→plan→implement→review_code→merge_docs→archive→commit_push (8 steps). `spec_delta` has NO creating step; `artifacts: []` on the new task.
- `ready-steps` → `brief` only; `status` → progress 0/8 (NOT 9), no blockers.
- `owl spec merge TASK-0008` (no delta) → `{ok:true, applied:false, reason:"no_spec_delta"}`, exit 0, wrote nothing.
- `TaskMerger.locate_delta` treats `:unknown_workflow_artifact` (workflows that do not declare `spec_delta`) AND an absent file as `skip:true`, so `owl spec merge` is a clean no-op for every workflow/task.
- The `optional: true` artifact-map flag is a recognized descriptor field (surfaced like `multiple` in `task_artifact_resolver.rb`), not an unknown key — it does not break workflow validation and is honoured.

## Gate semantics — VERIFIED, matches documented design

`merge_task` returns `ok = trace.valid` (strict). Probed a delta whose
scenario carries a dangling `- TEST:` ref: result was `ok:false,
applied:true`, exit 1, and the spec file WAS written (md5 changed; trace
reported the dangling scenario). The delta is intentionally NOT rolled
back — the merged spec is the new contract, the trace is the "link
tests" gate signal. This is the documented decision in the design and in
`TaskMerger`'s comments, and the `merge_docs` context instructs
resolving the trace failure before completing the step. Trace IS run
with `strict: true`. No issue.

## Dry-run — VERIFIED no-write

`owl spec merge TASK --dry-run` on an existing domain left the spec md5
unchanged. Delegates to P4 `apply(dry_run: true)` which skips
`write_spec`. No write occurs.

## Error propagation — VERIFIED, nothing written on P4 errors

- Missing `domain` front matter → `spec_delta_missing_domain` (exit 1).
- Invalid domain slug → `invalid_domain` (exit 1).
- ADDED requirement that already exists → `delta_conflict` (exit 1), md5 UNCHANGED (nothing written).
P4 hard errors abort before any write, as designed.

## spec_delta artifact type — VERIFIED

`artifact-type validate spec_delta` → valid. Front matter requires
`domain`+`status` (enum draft|merged). `required_patterns` mandates a
`## ADDED|MODIFIED|REMOVED Requirements` heading so an empty delta fails.
Seeded template validates. Active and seed copies of `artifact.yaml` and
`templates/default.md` are byte-identical (diff empty).

## merge_docs context — VERIFIED

Instructs running BOTH `owl publish` and `owl spec merge`, treating
`no_publishable_step`/`no_spec_delta` as normal no-ops, and requires the
trace gate to pass when a delta is present. Active and seed
`merge_docs.context.md` are byte-identical.

## FS-access / coverage — VERIFIED

No raw `File`/`Dir`/`Pathname`/`IO` in new `lib/owl/specs/**` (all I/O
via `Storage::Api`/`Artifacts::Api`/`SpecLocator`). `specs/api.rb` 100%.

## Minor 1 (by-design): dry-run on a brand-new domain → spec_not_found

`owl spec merge TASK --dry-run` for a domain whose `specs/<domain>/spec.md`
does not yet exist returns `spec_not_found` (exit 1), because dry-run
delegates to `apply(dry_run:true)` → `MergeEngine.prepare` →
`SpecLocator.read`, which has no spec to read. Severity: minor. The
real (non-dry) merge handles domain creation correctly (`created:true`,
verified), and `merge_docs` runs the real merge, not dry-run, so the
workflow path is unaffected. Pre-flagged by the implementer.

## Minor 2 (by-design): merge is not idempotent after a successful apply

`TaskMerger` reads only `domain`; it ignores the delta's `status`
(draft|merged) field. Re-running `owl spec merge` after a delta has
already been applied raises `delta_conflict` (the ADDED requirement now
exists). Practical impact on the gate-fail recovery loop: after a
gate-fail the delta is already written, so re-running `owl spec merge` to
re-check the gate fails with `delta_conflict` rather than re-tracing —
the operator must run `owl spec trace <domain> --strict` directly. The
`status` field is currently cosmetic. Severity: minor; matches the
design (status-based skip was never specified). Surfaced as a follow-up.

## Minor 3 (cosmetic): empty `specs/` dir during probing

A real (non-dry) merge to a new domain creates `specs/<domain>/spec.md`;
removing the domain can leave an empty `specs/` dir. Not a code defect;
cleaned up during review.

# Resolution

- Backward-compat guarantee: VERIFIED by fresh-task probe + no-delta merge + cross-workflow skip. No change needed.
- Gate semantics: VERIFIED (ok:false + delta applied, no rollback, strict trace). Matches documented design. No change needed.
- Dry-run no-write: VERIFIED (md5 stable). No change needed.
- Error propagation (missing/invalid domain, delta_conflict): VERIFIED, nothing written on P4 errors. No change needed.
- Artifact type, seed parity (artifact.yaml, template, workflow.yaml, merge_docs.context.md), FS-access, and `specs/api.rb` 100% coverage: VERIFIED. No change needed.
- Minor 1 (dry-run on absent domain): accepted as a documented limitation; real-merge path (used by merge_docs) is correct. No fix this task.
- Minor 2 (non-idempotent re-merge / cosmetic `status`): accepted by-design; recorded as a follow-up for a future task (status-based skip or post-merge auto-flip).
- Minor 3 (empty `specs/` dir): cleaned up; throwaway `TASK-0008` deleted; `tasks/index.yaml` clean of it.

No blocker or major findings. Setting `status: resolved`.
