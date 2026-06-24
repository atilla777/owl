---
status: resolved
summary: "P2-A conditional steps reviewed against the approved design: ready_resolver stays pure, owl next stays read-only, owl step skip unchanged, no skip/dispatch loop, missing artifact → met:false (no wedge), schema+validate solid, full back-compat with tests. Accepted with two non-blocking follow-ups."
verdict: accepted_with_followups
ready: true
---

# Summary

Reviewed the `review_code` diff for TASK-0028 (engine P2-A — conditional `when:`
steps + auto-skip) against the approved `design` artifact, with focus on the
architecture constraints flagged as engine-sensitive. The implementation matches
the design faithfully and is correct, well-tested, and fully back-compatible.

Objective gate is green: `bundle exec rspec` → 1934 examples, 0 failures, 1
pre-existing pending; SimpleCov 100% line-coverage gate on `lib/owl/**/{api,result}.rb`
passes (exit 0). RuboCop on changed files: net-zero NEW offenses (4 reported, all
verified pre-existing via `git stash`).

# Findings

All critical invariants from the design were verified true. No defects found.

### Architecture invariants (all CONFIRMED)

- **`ready_resolver.rb` is byte-for-byte unchanged** — `git diff` on
  `lib/owl/workflows/internal/ready_resolver.rb` is empty. The conditional gate
  runs in `Workflows::Backends::Filesystem#apply_conditional_gate`, the layer that
  owns `@root`, AFTER the pure resolver returns `ready` (alongside the existing
  children / plan-approval gates). Resolver purity preserved.
- **`owl next` stays read-only.** `NextActionResolver` adds the new
  `skip_conditional_step` action only; it reads `ready_steps` and classifies. No
  state write was added to the next/classify path. The mutation (skip) is the
  orchestrator's job, mirroring `await_plan_approval`.
- **`owl step skip` validation UNCHANGED.** `git diff` on `lib/owl/steps/api.rb`
  is empty. The auto-skip reuses the existing `skip` (which already rejects only
  `done` steps, so it accepts a non-optional conditional step). Confirmed.
- **ConditionEvaluator reads THROUGH the layer.**
  `Owl::Artifacts::Api.resolve` → `Owl::Storage::Api.read`, never raw FS.
  `matches`/`not_matches` semantics correct (exactly-one operator enforced).
  MISSING / undeclared / unreadable artifact → `Result.ok(met: false)` (no wedge,
  no crash) — verified in code (`read_body` returns nil → `met: false`) and tests.
- **Classification additive.** False-predicate step is moved out of `ready` into
  the NEW `conditional_skip` bucket; `blocked_by_children`, `awaiting_plan_approval`,
  and `ready` are intact. `owl task ready-steps --json` surfaces `conditional_skip`
  (verified live on TASK-0028: key present).
- **No starvation / no infinite loop.** Traced the loop:
  `conditional.any?` is classified BEFORE `dispatch_step`, so the gating step is
  cleared first; orchestrator runs `owl step skip … --reason condition_unmet`; the
  step becomes `skipped` (done-like) so it leaves the `ready` set permanently and
  cannot re-surface in `conditional_skip`; the next `owl next` dispatches the now-
  unblocked dependent. The `next_spec` exercises this exact sequence
  (skip_conditional_step → step skip → dispatch_step `plan`). A step without
  `when:` never enters this path.
- **Schema + validate.** `schemas/workflow.json` gains the `when` object
  (`additionalProperties:false` inside it). `StepWhenCheck` rejects malformed
  predicates (non-mapping, empty `artifact`, not-exactly-one operator, empty
  operator string, uncompilable regex) with precise `/steps/N/when…` paths and
  warns (non-fatally) on an undeclared `when.artifact` key. The seeded `feature`
  workflow still validates `ok:true` (back-compat).
- **Back-compat.** A step without `when:` skips predicate evaluation entirely
  (`conditional_predicate` returns nil → `next false`), zero added cost. Covered
  by an explicit "leaves a step without when: unchanged" test in the gate spec
  and validator spec.
- **Coverage / version.** api.rb 100% gate green (no api.rb file was modified —
  all new logic lives in `internal/` + `backends/` + an additive Result key, which
  is consistent with the design's "evaluate in the layer with root, not the public
  facade"). `Owl::VERSION` 0.14.0 → 0.15.0 (correct MINOR for an additive feature);
  CHANGELOG entry present and accurate; `skills/owl-orchestrator/SKILL.md`
  documents handling `skip_conditional_step` (skip + loop + back-compat note).

### Tests

Strong, multi-layer coverage:
- `condition_evaluator_spec.rb` — invalid-predicate branches + unresolvable
  artifact → `met:false` (safe default).
- `api_ready_steps_conditional_gate_spec.rb` — real artifact-body matching:
  true→ready, false→`conditional_skip`, dependent unblocks after skip,
  `not_matches` both polarities, missing artifact→skip, CLI surfacing, back-compat.
- `workflow_validator_when_spec.rb` — both operators accepted, both/neither
  rejected, empty/blank artifact, uncompilable regex, non-mapping, undeclared-key
  warning, back-compat.
- `next_spec.rb` (additions) — `skip_conditional_step` → skip → `dispatch_step`
  loop, and true-predicate → `dispatch_step`.

# Resolution

No defects to fix; verdict `accepted_with_followups`. The two items in
"Residual risks" are deliberate, documented design choices that do not block
merge — captured as follow-ups for future hardening, not changes required here.

# Remediation

None required. The diff is mergeable as-is.

# Residual risks

1. **Runtime fail-open for an invalid predicate (deliberate).** If a predicate is
   malformed at RUNTIME (`ConditionEvaluator` → `err(:invalid_condition)`),
   `apply_conditional_gate` leaves the step in `ready` (fail-open) rather than
   skipping it. This is the correct trade-off here — fail-open never silently
   drops work, and `owl workflow validate` is the authoring-time guard against
   malformed `when:` shapes. Documented in the evaluator/gate comments and the
   implement report. Low risk; no action.

2. **A task parked SOLELY on a false-conditional step is not auto-selected by the
   availability scanner.** `Tasks::Internal::AvailabilityScanner#build_candidate`
   returns nil when `ready_ids.empty?`; a false-conditional step lives in
   `conditional_skip`, not `ready`, so such a task is excluded from
   `owl task claim --next` / auto-select — identical to the existing behavior for
   `awaiting_plan_approval`-only and `blocked_by_children`-only tasks (consistent,
   not a regression). In the normal orchestrator flow the task is the CURRENT
   pointer, so `owl next` resolves it via `current_pointer` and returns
   `skip_conditional_step` regardless of the scanner — fully driveable. The only
   narrow gap: a fresh, unclaimed task whose head step is conditional-false would
   need `owl task use` before `owl next` can skip it; it will not be picked up by
   bare auto-select. Out of this task's scope (single-step conditional skip);
   worth considering if/when `claim --next` should advance conditional-only tasks.
