---
status: resolved
summary: "Objective verification gate matches the design contract; correct, fully green, api.rb at 100% coverage. Approved with non-blocking follow-ups on untested subprocess-safety + standalone owl verify paths and one dead helper."
verdict: accepted_with_followups
ready: true
---

# Code review — TASK-0012 objective verification gate

## Summary

The implementation faithfully realizes the design's binding decisions. Objectivity
holds: `Owl::Verification::Internal::Engine.classify` derives status purely from the
command's exit code (`0 → passed`, non-zero → `failed`, timeout/spawn-error → `failed`)
and `ReportWriter` overwrites `verification.md` itself — the agent cannot author a green
status (covered by spec "agent cannot override"). The completion gate lives in
`Owl::Steps::Api.complete` for `verify: true` steps: a non-passed objective status returns
a structured `:verification_failed` error (exit != 0) and leaves the step `running`
(`merge_docs` stays not-ready); `partial` passes with a `verification_partial` warning;
absent `settings.verification.command` is fail-open with a `verification_gate_inactive`
warning. `workflows/feature/workflow.yaml` correctly moves `verify: true` +
`creates: [review, verification]` onto `review_code` and drops `creates: [verification]`
from `implement`. Config validation (`validate_settings_verification`) is back-compatible
(absent → inactive) with sane error codes. Subprocess execution uses `Open3.popen3` with
`pgroup: true` and a process-group `TERM` on timeout, and the block form's `wait_thr.join`
prevents zombies/hangs. Layering is respected: FS writes go through `Storage::Api`, config
through `Config::Api`, artifact paths through `TaskArtifactResolver`; `api.rb` files are thin
facades. Freshness is by-construction (run at complete time); no stale-result path exists.

Verification ran green: `bundle exec rspec` → 1652 examples, 0 failures, 1 pending (the
pre-existing SQLite concurrent-write pending). `bundle exec rubocop` reports only the 3
pre-existing offenses in `validate_settings_storage`/`_language` (validator.rb:153/180/193),
none introduced by this change. Per-file coverage: `lib/owl/verification/api.rb`,
`lib/owl/steps/api.rb`, `lib/owl/cli/api.rb` all at 100% line coverage (docs/agents/30 met).

## Findings

- [info] Gate placement deviates from the design prose ("После OutputValidator.call"):
  the gate runs BEFORE `OutputValidator` in `complete`. This is a beneficial/necessary
  deviation — the gate authors `verification.md`, which `OutputValidator` then validates
  as one of `review_code`'s required artifacts. Running it after would fail validation on a
  not-yet-written artifact. No change needed; the design text is now slightly stale.
- [medium] Subprocess-safety paths in
  `lib/owl/verification/internal/command_runner.rb` are untested (timeout group-kill,
  `drain`, `terminate`, and the spawn-error `rescue` → `exit_code: nil`). Every spec injects
  a fake runner, so the riskiest real-process code (the actual `Open3`/`Timeout`/group-kill
  logic) has no coverage. Recommend one integration test with real builtins: a `sleep` that
  trips a sub-second timeout (asserts `timed_out` + process reaped) and a path that forces
  the `rescue` (e.g. a missing `chdir`) to assert `exit_code: nil`.
- [medium] The standalone `owl verify` CLI command
  (`lib/owl/cli/internal/commands/verify.rb`, design decision #6) is essentially untested
  (14/36 lines); `run`/`run_command`/`inactive`/`parse_options` are uncovered. Not an
  `api.rb` so not coverage-mandated, but a design-surfaced command shipping without a spec.
- [low] `Owl::Verification::Internal::Gate.resolve_step_id` is dead code — defined and
  documented as "used by standalone tooling," but no caller exists (the gate keys off the
  `step_id` being completed via `verify_step?`, not this resolver). Either wire it or drop it.
- [low] `partial` status is unreachable in production: `Engine.classify` only emits
  `passed`/`failed` (timeout → `failed`), so `Gate#decide`'s `partial` branch fires only via
  stubbed `Engine.run` in specs. Consistent with the design (timeout → failed), but the
  partial handling is currently aspirational/defensive — worth a comment or removal.
- [low] Run-error vs test-failure distinction is only partial: a not-found command executed
  through the shell yields exit 127 (classified `failed`), not the `run_error`/`exit_code:nil`
  path; only `popen3` spawn failures (e.g. bad chdir) reach `run_error`. Both still block, so
  behavior is safe; just narrower than the design's "different messages for both" framing.

## Resolution

No blocking issues. The change is correct, regression-free, and ship-ready as-is; merge is
recommended. All findings are non-blocking and captured as follow-ups below rather than
demanded as pre-merge fixes. Production code was not modified during this review (no clear
correctness bug found).

## Remediation

Suggested (non-blocking) follow-up backlog items:
1. Add a real-subprocess test for `CommandRunner` covering timeout group-kill and the
   spawn-error (`exit_code: nil`) path.
2. Add a spec for the `owl verify` CLI command (configured → JSON `gate_active:true`;
   unset → `gate_active:false` + warning; missing TASK-ID → `invalid_arguments`).
3. Remove or wire `Gate.resolve_step_id`; decide whether `partial` is a real engine output
   or drop its defensive branch.

## Residual risks

- Long synchronous runs inside `step complete` can outlive the claim lease (already noted in
  the design Risks and mitigated by the 1800s default timeout + the heartbeat guidance added
  to `review_code.context.md`); a heartbeat-during-run remains a possible future improvement.
- The untested subprocess-safety code is the main residual quality risk: if `TERM` is
  ignored by a child that does not honor signals, `wait_thr.join` could block until the
  process exits. Acceptable for typical test runners; the follow-up test would harden it.
