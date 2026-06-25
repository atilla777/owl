---
status: resolved
verdict: accepted
ready: true
summary: "owl step reset now releases the per-task active-step lock, fixing the wedge where a reset task rejected any later step start/complete with `active-step lock relates to a different step`. The new private clear_active_step_lock mirrors step complete: it loads the lock, gates the clear behind ActiveStepLock.matches? for the reset step, and no-ops when no lock is present. Verified by code reading against step_complete.rb, 3 new targeted specs (release / no-op / different-step-untouched), full suite green (1963 examples, 0 failures, 1 pre-existing pending, exit 0), rubocop net-zero on both touched files, and a live CLI smoke (start→lock, reset→lock gone, restart succeeds). Api unchanged; patch bump 0.16.0→0.16.1 + CHANGELOG Fixed entry correct. Verdict: accepted."
---

# Summary

Independent review of TASK-0031 — a bugfix making `owl step reset` release the
per-task active-step lock (`.owl/local/active_steps/<TASK>.yaml`). Before the
fix, `reset` moved the step status back to `pending` but left the lock pointing
at the reset step, wedging the task: any later `step start` / `step complete` of
another (or the same) step was rejected with `active-step lock relates to a
different step`.

I verified every review-focus point against the code, the `step complete`
reference, the new specs, the full suite, RuboCop, and a live CLI smoke test.
No defects found. Verdict: **accepted**.

Production change reviewed: `lib/owl/cli/internal/commands/step_reset.rb`
(added `require_relative '../../../steps/internal/active_step_lock'`, a
`clear_active_step_lock(root:, options:)` private helper, and a single call to
it after a successful `Api.reset`). Tests: 3 new examples in
`spec/owl/cli/step_commands_spec.rb`. Versioning: `lib/owl/version.rb`
0.16.0→0.16.1, `CHANGELOG.md` `[0.16.1]` Fixed entry, `Gemfile.lock` version
sync. No `lib/**/api.rb` was touched.

# Findings

All six review-focus points checked; each confirmed by code and/or test.

1. **Correctness of the fix — OK (high-priority #1).** After a successful
   `Owl::Steps::Api.reset`, `step_reset.rb:34` calls `clear_active_step_lock`.
   The helper (lines 55-63) loads the lock, returns early unless
   `lock.ok? && lock.value` (no-op when absent / on load error), then returns
   early unless `ActiveStepLock.matches?(lock.value, task_id:, step_id:)`, and
   only then calls `ActiveStepLock.clear`. This is the exact mirror of
   `step_complete.rb`: `complete` clears unconditionally at line 42 because it
   already gated on `matches?` upfront via `lock_mismatch_response` (lines
   85-90, which *rejects* on mismatch); `reset` has no upfront gate, so it
   inlines the same `matches?` guard before clearing. Semantically equivalent and
   correct. `ActiveStepLock.clear` is itself a no-op (`Result.ok(:absent)`) when
   the file is missing, so the guard is belt-and-suspenders safe.

2. **No clobbering of a foreign lock — OK (high-priority #2).** The clear is
   genuinely gated by `matches?`, not unconditional: `matches?` compares both
   `task_id` AND `step_id` of the lock payload against the reset request
   (`active_step_lock.rb:87-91`). The new spec *"reset leaves a lock that refers
   to a different step untouched"* writes a drifted lock with `step_id: b`,
   resets step `a`, and asserts the lock still exists with `step_id == 'b'`. This
   directly exercises the `return unless matches?` branch — if the guard were
   removed/wrong, that test would fail. Confirmed by reading and by the green
   suite.

3. **Api untouched — OK.** `git diff` shows zero changes to
   `lib/owl/steps/api.rb` and `lib/owl/cli/internal/commands/step_complete.rb`.
   The lock is treated as a CLI/runtime concern, consistent with the existing
   architecture where `step start`/`step complete` manage the lock at the CLI
   layer, not in `Steps::Api`. No `**/api.rb` modified, so the 100% public-API
   coverage gate is unaffected (suite exits 0 ⇒ gate passed).

4. **Task is freed — OK.** Spec *"reset releases the active-step lock so the task
   is free again"* asserts: lock exists after `step start`, is gone after
   `step reset` (exit 0), and a fresh `step start` of the same ready step then
   returns `step.status == 'running'` (exit 0) — i.e. no `different step` /
   `active_step_locked` rejection. My live smoke reproduced this exactly
   (start→lock present, reset→lock gone, restart→`ok:true status:running`).

5. **Idempotency / edge — OK.** Spec *"reset succeeds when no active-step lock is
   present (no-op clear)"* deletes the lock before reset and asserts exit 0 with
   no lock — covering the `return unless lock.value` early-out. The command's
   JSON success payload (`ok`, `task_id`, `step`, resolved-source fields,
   `task_path`) is unchanged: the lock clear is a side effect inserted between
   the `Api.reset` success check and payload construction, touching neither the
   payload shape nor output.

6. **Versioning + CHANGELOG — OK.** `Owl::VERSION` 0.16.0→0.16.1 — a PATCH bump,
   correct per Constitution §7.1 (back-compat bugfix). `CHANGELOG.md` adds a
   `[0.16.1] - 2026-06-25` block under `### Fixed` accurately describing the
   wedge, the `.owl/local/active_steps/<TASK>.yaml` lock, the rejection message,
   and the match-gated / no-op-on-absent semantics. `Gemfile.lock` synced to
   0.16.1 (expected).

**Observation (not a defect):** `.owl/local/active_steps/` in this repo carries
several stale lock files for already-archived tasks (TASK-0016..0029). These are
pre-existing leftovers unrelated to this change (this very fix is the kind that
prevents such residue from `reset` going forward); not in scope.

# Resolution

Accept. The fix is a minimal, correct mirror of `step complete`'s lock handling,
with the critical `matches?` guard proven by a dedicated negative test so a
foreign lock is never clobbered. Both highest-risk concerns (fix correctness and
no-clobber) are satisfied by code and test, corroborated by a live CLI smoke run.
Full suite green and exit 0, RuboCop net-zero on the touched files, no
public-API coverage impact. No code changes required. `status: resolved`,
`verdict: accepted`.

# Remediation

None required.

# Residual risks

- Pre-existing repo warts unchanged: 1 pending storage-contract spec
  (`storage concurrent writes`); README test-isolation wart (did not trigger
  this run — README stayed clean, no checkout needed); stale archived-task lock
  files under `.owl/local/active_steps/`.
- `tasks/index.yaml` and `tasks/TASK-0031/` carry the working change for
  TASK-0031 itself (expected, not a defect).
