---
status: resolved
verdict: accepted
summary: "Independent, adversarial review of TASK-0037 — making conditional-skip steps count toward task availability so auto-select (`owl next` without a current pointer, `owl task claim --next`) and `owl task available` no longer hide a task whose only next move is a false-`when:` skip. The fix renames `AvailabilityScanner.ready_step_ids` → `actionable_step_ids` and unions `value[:ready]` ids with `value[:conditional_skip]` ids from a SINGLE `Owl::Workflows::Api.ready_steps` call; `build_candidate` gates `empty?` on the union and `candidate_hash[:ready_step_ids]` carries the union. I confirmed the four load-bearing invariants against the code. (#1 actionable correctness) Both buckets come from ONE `ready_steps` result (availability_scanner.rb:99-104), not two calls; `conditional_skip` entries are `{ id:, reason: }` (filesystem.rb:369 `apply_conditional_gate` appends `{ id: entry[:id].to_s, reason: CONDITION_UNMET_REASON }`), so `.map { |step| step[:id] }` is exactly right and yields `'design'`. (#2 ready regression) For a task with a `ready` step, `actionable ⊇ ready`, so the `empty?` gate is unchanged ⇒ availability and `sort_candidates` (untouched: sorts by `[-priority, created_at, task_id]`) are identical; the regression spec proves `ready_step_ids == ['a']`. (#3 waiting excluded) Only `:ready` and `:conditional_skip` are read; `:blocked_by_children` and `:awaiting_plan_approval` are NEVER touched, so a merely-waiting task stays unavailable. (#4 deps intersection intact) `ready_availability_scanner.rb` and `next_action_resolver.rb` are NOT in the diff (verified `git diff --name-only` empty for both); the resolver still classifies `conditional.any?` BEFORE `ready.any?` (next_action_resolver.rb:63-71), so an auto-selected conditional-only task resolves to `skip_conditional_step`. The new unit spec stubs `Owl::Workflows::Api.ready_steps` with the realistic shape `Result.ok(ready:, conditional_skip:)` and asserts conditional-only ⇒ available with `ready_step_ids=['design']`, both-empty ⇒ not available, ready ⇒ available (regression), and union ⇒ `%w[a design]` — not fake. Objective verification: `bundle exec rspec` → 1984 examples, 0 failures, 1 pre-existing pending, exit 0 (SimpleCov public-API 100%-line at_exit gate did NOT trip ⇒ `**/api.rb` coverage holds); README NOT dirtied (no checkout needed); `bundle exec rubocop` on both changed files → 2 files, no offenses. I also ran an INDEPENDENT throwaway-project end-to-end smoke (not the implementer's spec): a `feat` workflow whose `design` step carries `when: { artifact: brief, matches: <pattern-absent-from-brief> }`; after completing `brief`, `ready-steps` put `design` in `conditional_skip` (ready empty), with NO current pointer `owl task available --json` returned TASK-0001 with `ready_step_ids=['design']`, and `owl next --json` auto-selected TASK-0001 and emitted `action.kind=skip_conditional_step` on `design` (reason `condition_unmet`). This is precisely the bug the change fixes, proven live. Version minor 0.19.0→0.20.0 and the CHANGELOG entry are correct for a new observable auto-select behavior; `availability_scanner.rb` is internal (no 100%-api gate on it). No defects. Verdict: accepted."
---

# Summary

Independent, adversarial review of TASK-0037 — a single-production-file change to
`Owl::Tasks::Internal::AvailabilityScanner` that makes a task whose only next
move is a conditional skip (a step held out of `ready` by a false `when:`
predicate, TASK-0028) count as *available* for auto-selection. Before the change,
availability keyed strictly on the presence of a dispatchable `ready` step, so a
conditional-only task was advanced by `owl next` (with an explicit/current task —
the resolver already handles `conditional_skip`) yet was invisible to
auto-select (`owl next` without a current pointer, `owl task claim --next`) and
to `owl task available`. The fix renames `ready_step_ids` → `actionable_step_ids`
and returns the union `value[:ready]` ids ∪ `value[:conditional_skip]` ids from a
single `ready_steps` call; the `empty?` gate and the candidate's
`ready_step_ids` field both use that union.

Because this is an availability/auto-select change I treated four failure modes
as primary: a wrong/double `ready_steps` call, a regression for normal ready
tasks, accidental inclusion of waiting states, and breakage of the deps-aware
intersection. I verified each against the code, the conditional-gate backend, the
resolver, the unit spec, the full suite, RuboCop, and an INDEPENDENT live
end-to-end smoke I wrote myself. No defects found. Verdict: **accepted**.

Production change reviewed:
- `lib/owl/tasks/internal/availability_scanner.rb` — `ready_step_ids` →
  `actionable_step_ids`; returns `ready_ids + conditional_ids` from one
  `Owl::Workflows::Api.ready_steps` result. `build_candidate` gates on the union;
  `candidate_hash[:ready_step_ids]` carries the union. `sort_candidates`,
  `active_entries`, `live_claim?`, `priority_of` unchanged.
- `lib/owl/version.rb` 0.19.0→0.20.0; `CHANGELOG.md` `[0.20.0]` entry.
- `spec/owl/tasks/internal/availability_scanner_spec.rb` — new, 4 examples.

# Findings

All seven review-focus points checked against code, backend, resolver, the
suite, RuboCop, and a live independent smoke. Each confirmed.

1. **Actionable correctness — CONFIRMED.** `actionable_step_ids`
   (availability_scanner.rb:98-105) issues exactly ONE
   `Owl::Workflows::Api.ready_steps` call and unions `Array(result.value[:ready])`
   ids with `Array(result.value[:conditional_skip])` ids. The
   `conditional_skip` bucket is produced by
   `Filesystem#apply_conditional_gate` (filesystem.rb:358-373), which appends
   `{ id: entry[:id].to_s, reason: CONDITION_UNMET_REASON }` — a `{id:, reason:}`
   hash — so `.map { |step| step[:id] }` is correct and never raises on the
   `reason` key. `Array(...)` guards a nil/absent bucket. No second call, no
   re-scan.

2. **Ready regression — CONFIRMED.** When a task has a `ready` step,
   `actionable ⊇ ready`, so the `return nil if actionable_ids.empty?` gate yields
   the same availability decision as before. `sort_candidates` (line 112-114,
   `[-priority, created_at, task_id]`) and `candidate_hash`'s other fields are
   untouched. The regression spec asserts a ready-only task stays available with
   `ready_step_ids == ['a']`.

3. **Waiting states excluded — CONFIRMED.** The scanner reads only `[:ready]` and
   `[:conditional_skip]`. `[:blocked_by_children]` and
   `[:awaiting_plan_approval]` (both populated by `ready_steps`) are never
   referenced, so a task that is merely waiting on children or plan approval
   stays out of the available pool. This is the intended waiting-vs-actionable
   distinction and matches the inline rationale comment.

4. **deps intersection intact — CONFIRMED.** `git diff --name-only` is empty for
   both `lib/owl/tasks/internal/ready_availability_scanner.rb` (TASK-0030) and
   `lib/owl/orchestration/internal/next_action_resolver.rb` — neither was
   touched. The deps-aware `ReadyAvailabilityScanner` intersects deps+status
   eligibility with this scanner's output; a conditional-only task that passes
   deps now appears in the base availability set, so it survives the
   intersection rather than being dropped.

5. **Resolver untouched — CONFIRMED.** `next_action_resolver.rb` is not in the
   diff and still classifies `conditional.any?` BEFORE `ready.any?`
   (next_action_resolver.rb:63-71) via `skip_conditional_action`. So once
   auto-select surfaces a conditional-only task, the resolver returns
   `skip_conditional_step`, which the orchestrator advances — closing the loop
   the bug left open.

6. **Test honesty — CONFIRMED.** The spec stubs
   `Owl::Workflows::Api.ready_steps` with `Owl::Result.ok(ready:,
   conditional_skip:)` — the real result shape for the keys the scanner reads —
   and uses real `cli init` + `task create` to materialize a genuine index entry,
   so `scan` exercises the real `active_entries`/`build_candidate`/`candidate_hash`
   path and only the workflow query is faked. The four cases (conditional-only ⇒
   `['design']`; both empty ⇒ not available; ready ⇒ `['a']`; union ⇒
   `%w[a design]`) pin exactly the behavior under review. Not a tautology.

7. **Version + CHANGELOG — CONFIRMED.** New observable auto-select behavior is a
   backward-compatible feature ⇒ minor bump 0.19.0→0.20.0 is correct; Gemfile.lock
   re-resolved to 0.20.0; the `[0.20.0]` CHANGELOG entry accurately describes the
   union and the preserved waiting/ready behavior. `availability_scanner.rb` is
   `tasks/internal/`, not a public `api.rb`, so the 100%-line public-API gate does
   not bind it; that gate nonetheless held in the full run.

# Resolution

No changes required. The implementation is correct, minimal, and confined to the
single internal scanner. The four invariants that could have produced regressions
(double-call, ready regression, waiting inclusion, deps/resolver breakage) all
hold. The independent end-to-end smoke reproduced the exact pre-fix bug and
showed it fixed: a conditional-only task is now both *available* and
auto-selected to `skip_conditional_step`.

# Remediation

None. Accepted as-is.

# Residual risks

- **Union ordering is `ready + conditional` (ready first).** The candidate's
  `ready_step_ids` therefore lists ready steps before conditional ones. No
  consumer depends on intra-list order (the resolver re-queries `ready_steps`
  itself and prioritizes conditional independently), so this is cosmetic; noted
  only for completeness.
- **`ready_step_ids` key now also carries non-ready (conditional-skip) ids.** The
  field name is slightly less literal than its contents. The inline comment
  documents this and the JSON contract field name is unchanged (no rename), so
  back-compat for consumers is preserved; a future rename to `actionable_step_ids`
  in the JSON payload would be a breaking change and is intentionally NOT done
  here.
- **Scanner-level unit relies on the `ready_steps` result shape.** If a future
  change to `Filesystem#ready_steps` renamed/dropped the `conditional_skip` key
  or changed its entry shape from `{id:, reason:}`, the stubbed unit would not
  catch it; the existing `api_ready_steps_conditional_gate_spec.rb` integration
  spec and the live smoke are the real guards on that contract.
