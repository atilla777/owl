---
status: approved
summary: "Wire the spec layer into the feature workflow: an optional spec_delta task artifact plus a deterministic `owl spec merge TASK-ID` that applies the delta into the living spec (P4) and gates on traceability (P5), invoked by merge_docs and gracefully skipped when a task declares no delta."
---

# Problem

P4 shipped a deterministic spec delta-merge engine and P5 a `owl spec trace` coverage checker,
but neither is connected to the workflow: `merge_docs` still only runs `owl publish` (a no-op for
`feature`, `no_publishable_step`), and nothing runs the trace gate. So updating the living spec
and enforcing scenario→test coverage are still manual. The two integrations were deliberately
deferred from P4/P5 because they touch every task's flow; this task does them safely and
optionally.

# Goal

Connect the spec engines to the `feature` workflow without breaking tasks that touch no spec:

- A `spec_delta` artifact type (markdown: front matter `domain` + `status`; sections
  `## ADDED Requirements`, `## MODIFIED Requirements`, `## REMOVED Requirements`), declared as an
  OPTIONAL artifact a task produces only when it changes a domain's behaviour.
- A deterministic `owl spec merge TASK-ID [--dry-run]`: if the task has no spec_delta artifact →
  graceful skip; else read its `domain`, apply the delta via the P4 engine, then run the P5 trace
  with `--strict` as a gate, returning a combined result.
- `merge_docs` runs `owl spec merge` (in addition to the existing `owl publish`), so the living
  spec updates deterministically and the trace gate fires — but only when a delta is present.
- Tasks with no spec_delta artifact see no behavioural change (merge_docs stays a no-op).

# Scenarios

### Requirement: merge applies a present delta and gates on traceability

The system SHALL, when a task declares a spec_delta, apply it to its domain's spec and report the
post-merge traceability.

#### Scenario: Task with a spec_delta merges and traces
- WHEN a task has a `spec_delta` artifact naming `domain: X` with valid ADDED/MODIFIED/REMOVED
  sections and `owl spec merge TASK-ID` runs
- THEN the delta is applied to `specs/X/spec.md` via the P4 engine
- AND `owl spec trace X --strict` is run and its result is included
- TEST: spec/owl/specs/merge_task_spec.rb (apply+trace example)

#### Scenario: Untraced result fails the gate
- WHEN the merged spec has a scenario with no `- TEST:` and merge runs with the strict gate
- THEN `owl spec merge` returns `ok:false` surfacing the untraced scenarios (delta still applied;
  trace is the gate signal)
- TEST: spec/owl/specs/merge_task_spec.rb (gate example)

### Requirement: merge is a graceful no-op without a delta

The system SHALL skip cleanly when a task declares no spec_delta, preserving current behaviour.

#### Scenario: Task without a spec_delta
- WHEN `owl spec merge TASK-ID` runs for a task that has no `spec_delta` artifact
- THEN it returns `{ok:true, applied:false, reason:"no_spec_delta"}` and writes nothing
- TEST: spec/owl/cli/spec_merge_command_spec.rb (no-delta example)

### Requirement: dry-run previews without writing

The system SHALL support a no-write preview.

#### Scenario: Dry run
- WHEN `owl spec merge TASK-ID --dry-run` runs
- THEN it reports the would-be merge + trace and the spec file on disk is unchanged
- TEST: spec/owl/cli/spec_merge_command_spec.rb (dry-run example)

### Requirement: merge_docs invokes merge without breaking spec-less tasks

The `feature` workflow's merge_docs step SHALL run `owl spec merge` and stay a no-op for tasks
with no spec_delta.

#### Scenario: merge_docs on a spec-less task
- WHEN merge_docs runs for a task with no spec_delta
- THEN the step completes with no spec writes (the existing `owl publish` no-op behaviour is kept)
- TEST: spec/owl/integration/merge_docs_spec_merge_spec.rb (spec-less example)

# Edge cases

- spec_delta present but missing `domain` front matter → structured `spec_delta_missing_domain`.
- spec_delta `domain` slug-validated (reuse P1 guard); invalid → `invalid_domain`.
- Delta errors (`delta_conflict`, `delta_target_missing`, `invalid_delta`, `merge_would_invalidate`)
  propagate from the P4 engine and abort the write.
- Ordering: apply first (P4 already re-validates grammar before writing), then trace; a trace
  failure does NOT roll back the applied delta (the spec is the new contract; trace is the
  "link tests" signal) — document this.
- `--dry-run` must not write the spec.
- merge_docs must remain backward compatible: spec-less tasks unaffected; the existing publish
  path still runs.
- The spec_delta artifact is OPTIONAL — its absence is normal, not an error.

# Acceptance criteria

- [ ] `spec_delta` artifact type registered (active + seed), with front matter `domain`/`status`
      and the three delta sections; `owl artifact-type validate spec_delta` passes.
- [ ] `spec_delta` declared as an OPTIONAL artifact in the `feature` workflow (no required step
      creates it).
- [ ] `owl spec merge TASK-ID [--dry-run]` + `Owl::Specs::Api.merge_task` implemented: graceful
      no-delta skip; apply via P4 engine; trace --strict gate; structured errors.
- [ ] `merge_docs` step context updated to run `owl spec merge TASK-ID`; spec-less tasks unchanged.
- [ ] Logic in `Owl::Specs` (public api.rb → 100% line coverage), storage roles, no raw File/Dir.
- [ ] RSpec: apply+trace, gate failure, no-delta skip, dry-run no-write, missing-domain, merge_docs
      backward-compat.
- [ ] `bundle exec rspec` green for touched areas; `bundle exec rubocop` clean (never `-A`).
