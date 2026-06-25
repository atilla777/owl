---
status: resolved
summary: "Deps+status-aware auto-selection implemented cleanly as an intersection of AvailabilityScanner with ReadyScanner at both selection sites (claim --next, orchestration auto-select); standalone `available`/`owl task available` stay dependency-blind; ReadyScanner dep semantics untouched; candidate shape/order preserved; layering respected (orchestration → Tasks::Api). rspec green (1960/0/1), SimpleCov public-API 100% gate passed, rubocop net-zero, live smoke confirms ready excludes / available includes a dep-blocked task."
verdict: accepted
ready: true
---

# Summary

Independent code review of TASK-0030 — making Owl task auto-selection deps+status-aware.
The change introduces `ReadyAvailabilityScanner` (intersection of `AvailabilityScanner` ∩
`ReadyScanner`) and routes the two auto-selection sites through it while leaving the
dependency-blind `available` path intact for the standalone command. I verified every review
focus point against the code and tests, ran the full suite, rubocop, and a live CLI smoke
test. No real defects found. Verdict: **accepted**.

Production changes reviewed: `lib/owl/tasks/internal/ready_availability_scanner.rb` (new),
`lib/owl/tasks/internal/ready_scanner.rb` (added `NON_READY_STATUSES` = terminal + on_hold/blocked),
`lib/owl/tasks/api.rb` (`available(root:, dep_aware: false)` keyword), `lib/owl/tasks/internal/claim_service.rb`
(`claim_next` now scans via `ReadyAvailabilityScanner`), `lib/owl/orchestration/internal/task_resolver.rb`
(`auto_select` calls `available(dep_aware: true)`), `lib/owl/version.rb` (0.15.1→0.16.0),
`CHANGELOG.md`. Tests: new `ready_availability_scanner_spec.rb`, new `orchestration/internal/task_resolver_spec.rb`,
extended `api_spec.rb` and `api_dependencies_spec.rb`. `Gemfile.lock` version sync (expected).

# Findings

All eight review-focus points checked; each confirmed by code and test.

1. **Regression — dep-blind `available` default preserved — OK (high-priority risk #1).**
   `Api.available(root:, dep_aware: false)` returns `with_backend(root, &:available)`, the exact
   pre-change path; the `dep_aware` branch is only taken when explicitly `true`. The CLI command
   `owl task available` passes no `dep_aware`, so it stays dependency-blind. Proven by two new
   tests: `stays dependency-blind by default: a dep-blocked task is still present` and
   `... an on_hold task is still present` (api_spec). Live smoke confirmed: `owl task available`
   listed the dep-blocked `TASK-0032`. Severity: none.

2. **Regression — "has a ready step" filter preserved via intersection — OK (high-priority risk #2).**
   `ReadyAvailabilityScanner.scan` starts from `AvailabilityScanner` candidates (which already
   require ≥1 dispatchable workflow step + no live claim) and `select`s only those whose id is in
   the `ReadyScanner` id-set. It is a true intersection, not a replacement — a dep-clear, workable
   task with no dispatchable step is still excluded because it never enters the AvailabilityScanner
   set. Proven by `excludes a task with no ready workflow step (available filter preserved)`
   (ready_availability_scanner_spec) and `preserves the "has a ready step" filter and the candidate
   hash shape` (api_spec, dep_aware context). Severity: none.

3. **Both selection sites changed; no dep-blind leak; layering respected — OK.**
   `ClaimService.claim_next` now calls `ReadyAvailabilityScanner.scan` (the `require_relative
   'availability_scanner'` was removed and replaced with `ready_availability_scanner`).
   `TaskResolver.auto_select` calls `Owl::Tasks::Api.available(root:, dep_aware: true)`. Neither
   reaches the dep-blind backend path for auto-selection. `TaskResolver` lives in the orchestration
   layer and reaches tasks only through `Owl::Tasks::Api` (never `Tasks::Internal::*` directly),
   honoring the layer rule. Proven by `task_resolver_spec` (`does not auto-select a dep-blocked top
   task`, `does not auto-select an on_hold top task`) and `api_spec` claim tests (`does not
   auto-claim a dep-blocked task with --next`, `... an on_hold task with --next`). Severity: none.

4. **Dependency-satisfaction semantics unchanged — OK.** `DEP_COMPLETE_STATUSES = %w[done archived]`
   and `deps_complete?` are byte-for-byte unchanged: a dependency counts as satisfied when done/archived
   (or absent from index), regardless of being on_hold/blocked. Only the task's OWN-status gate widened:
   `ready_entry?` now checks `NON_READY_STATUSES` (terminal + on_hold + blocked) instead of just
   `TERMINAL_STATUSES`. The two concerns are cleanly separated by the constant comments. The
   `api_dependencies_spec` keeps the existing dep-satisfaction tests and adds own-status on_hold/blocked
   exclusions. Severity: none.

5. **Candidate shape and order preserved — OK.** `ReadyAvailabilityScanner` returns
   `Result.ok(available: candidates)` where `candidates` are the original AvailabilityScanner hashes
   (`:task_id`, `:title`, `:kind`, `:priority`, `:created_at`, `:ready_step_ids`, `:reason`) filtered
   in place — `select` preserves AvailabilityScanner's priority/age/id sort order. So
   `claim_first_available` (`candidate[:task_id]`) and `auto_select` (`top[:reason]`, `top[:task_id]`)
   keep working. Proven by the shape assertions in `ready_availability_scanner_spec` (`ready_step_ids
   == ['a']`, reason a String) and api_spec, plus the `keeps priority/age sort order when filtering`
   test in api_dependencies_spec. Severity: none.

6. **Error propagation — OK.** `scan` returns `available_result` if it errs, then `ready_result` if
   it errs, before computing the intersection — so an error from either underlying scan short-circuits.
   Covered by `propagates an error when resolution fails` (ready_availability_scanner_spec, no project
   present). `claim_next` already returns early on `scan.err?`. Severity: none.

7. **Coverage gate — OK.** Suite exits 0, so the `spec_helper` `at_exit` gate (every
   `/lib/owl/(.+/)?(api|result)\.rb` at ≥100% line coverage, else `exit 1`) passed — including the
   extended `lib/owl/tasks/api.rb` whose new `dep_aware` keyword has both branches exercised (false
   path by the dep-blind tests, true path by the `dep_aware: true` context). Severity: none.

8. **Versioning / CHANGELOG — OK.** `Owl::VERSION` bumped 0.15.1 → 0.16.0 (MINOR — additive
   behavior change, correct per Constitution §7.1 SemVer). `CHANGELOG.md` has a `[0.16.0] - 2026-06-25`
   entry documenting the deps+status-aware auto-selection, the preserved "has a ready step" filter,
   the `owl task ready` behavior change (now hides on_hold/blocked), and the explicit Compatibility
   note that `owl task available` stays dependency-blind. Severity: none.

**Observation (not a defect):** `ReadyAvailabilityScanner` uses `Set.new` without an explicit
`require 'set'`. On Ruby 3.2+ `Set` is a preloaded core class, and this repo runs Ruby 3.3.4
(suite green), so it works today. A future move to an older Ruby or a stricter load path would
need the require; harmless now.

# Resolution

Accept. Every review-focus point is satisfied by the implementation and backed by a test; the two
highest-risk regressions (dep-blind `available` default and the preserved "has a ready step"
intersection filter) are both explicitly proven, and the live CLI smoke test corroborates the unit
tests (`owl task ready` excluded the dep-blocked task while `owl task available` included it). No
code changes required. `status: resolved`, `verdict: accepted`.

# Remediation

None required.

# Residual risks

- `Set` is used without `require 'set'` — safe on Ruby ≥3.2 (current 3.3.4); would break only on a
  pre-3.2 Ruby. Optional one-line hardening, not blocking.
- `tasks/index.yaml` carries the working change for TASK-0030 itself (expected, not a defect).
- Pre-existing repo warts unchanged: 1 pending storage-contract spec; README test-isolation wart
  (did not trigger this run).
