---
status: resolved
verdict: accepted
summary: "Independent, deadlock-focused review of TASK-0036 — wrapping `owl task delete`'s `FileUtils.rm_rf(tasks/<id>/)` in that task's own `TaskMutationLock.with_lock(task-<id>)` to close the delete-while-in-use hazard explicitly logged as a residual risk in the TASK-0035 review (a concurrent writer of the SAME task could have its task.yaml removed mid-write). I confirmed the three load-bearing invariants against the code: (#1) under `with_lock(deleted)` lives ONLY `FileUtils.rm_rf(task_dir)` + `Result.ok(:removed)` — nothing else (the new private `remove_dir_locked`, deleter.rb:66-73); (#2) `clean_dangling_refs` (which locks each OTHER task `task-<child>` one at a time) and `IndexWriter.rebuild` (the `index` lock) both run AFTER `remove_dir_locked` returns and `return removed if removed.err?` — OUTSIDE the deleted-task lock — so two parallel deletes never nest `lock(deleted)->lock(child)` and cannot form the classic A:X→Y / B:Y→X lock-ordering cycle; delete holds AT MOST ONE task lock at any instant; (#3) the `task_not_found` directory check (deleter.rb:27) is BEFORE the lock, so a missing task is never locked, and the `lock_held` err propagates honestly — `with_lock` returns the `locks.acquire` `:lock_held` Result unchanged when held past the 10s deadline, `remove_dir_locked` forwards it, and `call` returns it WITHOUT removing the dir. The return-typing is correct: the block yields `Result.ok(:removed)` so `removed.err?` is false on success and true on acquire-failure — one branch covers both. The lock file lives under `local_state` (`<root>/.owl/local/task-<id>.lock`), NOT inside task_dir, so it survives the rm_rf and is released in `with_lock`'s `ensure`. Public contract intact: `Tasks::Api.delete(root:, task_id:)` and `backends/filesystem.delete_task` are unchanged — the `locks:/clock:/sleeper:` injection is a back-compat add on `Internal::Deleter.call` only (default `Owl::Locks::Api`/`Time`/real `sleep`), used solely by the new spec. Objective verification: `bundle exec rspec` → 1980 examples, 0 failures, 1 pre-existing pending, exit 0 (public-API 100%-line SimpleCov gate did NOT trip ⇒ **/api.rb coverage holds); README not dirtied (no checkout); `bundle exec rubocop` on deleter.rb + api_delete_spec.rb → no offenses. I also ran an INDEPENDENT throwaway-project smoke (not the implementer's spec): normal delete removes the dir; foreign-token holder on `task-<id>` + a clock-double past the deadline ⇒ `Deleter.call` returns err code `:lock_held` with the directory STILL PRESENT and the lock file at `.owl/local/task-<id>.lock`. No defects. Verdict: accepted."
---

# Summary

Independent, adversarial review of TASK-0036 — a one-file concurrency hardening
of `owl task delete`. Before this change `Internal::Deleter.call` removed
`tasks/<id>/` via `FileUtils.rm_rf` WITHOUT holding the deleted task's own
`task-<id>` mutation lock, so a session mutating that same task (the tracker
mutators introduced in TASK-0035 deliberately do not take the claim lease) could
have its `task.yaml` deleted out from under a half-finished read-modify-write.
This is precisely the "delete-while-in-use" hazard the TASK-0035 review recorded
as Residual Risk #1. The fix wraps ONLY the `rm_rf` in
`TaskMutationLock.with_lock(root:, task_id:)` via a new private
`remove_dir_locked`, leaving `clean_dangling_refs` and `IndexWriter.rebuild`
outside that lock so two parallel deletes cannot form a lock-ordering deadlock.

Because this is a concurrency change I treated deadlock, lock-ordering and the
fail-safe `lock_held` path as the primary failure modes and verified each against
the code, the unit test, the full suite, RuboCop, and an INDEPENDENT smoke I
wrote myself (not the implementer's spec). No defects found. Verdict:
**accepted**.

Production change reviewed:
- `lib/owl/tasks/internal/deleter.rb` — `call` gains injectable
  `locks:/clock:/sleeper:` (defaults `Owl::Locks::Api`/`Time`/real `sleep`); the
  bare `FileUtils.rm_rf` is replaced by `remove_dir_locked(...)`, a new private
  method that takes the deleted task's `task-<id>` lock around `rm_rf` only and
  returns `Result.ok(:removed)`. `clean_dangling_refs` + `IndexWriter.rebuild` +
  `ClaimResetter` are unchanged and stay after the locked block.
- `lib/owl/version.rb` 0.18.0→0.19.0; `CHANGELOG.md` `[0.19.0]`.
- `spec/owl/tasks/api_delete_spec.rb` — one new `lock_held` spec.

# Findings

All six review-focus points checked against code, the suite, RuboCop, and a live
independent smoke. Each confirmed.

1. **Only `rm_rf` under the deleted-task lock — OK (the load-bearing
   invariant).** `remove_dir_locked` (deleter.rb:66-73) is the entire body wrapped
   by `with_lock(deleted)`, and that body is exactly two statements:
   `FileUtils.rm_rf(task_dir.to_s)` then `Result.ok(:removed)`. Nothing else is
   inside the block — no `clean_dangling_refs`, no `IndexWriter.rebuild`, no
   foreign-task lock. Verified by direct read of lines 67-72.

2. **No deadlock nesting — `clean_dangling_refs` and the rebuild are OUTSIDE the
   lock — OK.** In `call`, `remove_dir_locked` returns first (deleter.rb:35-38,
   with `return removed if removed.err?`); only THEN does line 40 run
   `clean_dangling_refs` (which itself locks each OTHER live task `task-<child>`
   one at a time, release-in-ensure each iteration, never two held) and line 42
   `IndexWriter.rebuild` (the `index` lock). So a delete holds AT MOST ONE task
   lock at any instant and never holds `lock(deleted)` while taking
   `lock(child)`. Two parallel deletes A(delete X)/B(delete Y) therefore cannot
   form the classic A: X→Y / B: Y→X cycle — the precise deadlock the comment and
   CHANGELOG warn against. Had `clean_dangling_refs` been moved INSIDE the lock,
   A holding `lock(X)` then taking `lock(Y)` while B holds `lock(Y)` taking
   `lock(X)` would deadlock to the 10s deadline; it is NOT inside. Lock ordering
   stays consistent with the rest of the codebase (`task -> index`, never the
   inverse): the locked rm_rf takes no inner lock, and the later rebuild takes the
   index lock with no task lock held.

3. **`task_not_found` is decided BEFORE the lock — OK.** The
   `task_dir.directory?` guard (deleter.rb:27-33) runs before `remove_dir_locked`,
   so a non-existent task returns `:task_not_found` without ever acquiring a lock.

4. **`lock_held` propagation is honest — OK, genuinely tested.** `with_lock`
   returns the `acquire` Result unchanged when it `.err?` (task_mutation_lock.rb:44-45);
   `acquire` returns the `locks.acquire` `:lock_held` Result once `clock.now >=
   deadline` (line 68). `remove_dir_locked` forwards that Result and `call` does
   `return removed if removed.err?` — so a held lock past the deadline yields the
   recoverable `:lock_held` and the `rm_rf` never runs. The new spec is honest:
   a FOREIGN token holds `task-<id>`, a `class_double(Time)` returns `now` then
   `now + ACQUIRE_TIMEOUT_SECONDS + 1` (one retry, then past deadline) with a
   no-op sleeper, and it asserts BOTH `result.code == :lock_held` AND that
   `tasks/<id>` still exists. I reproduced this independently (see verification.md):
   real foreign holder + clock-double ⇒ `:lock_held`, directory present, lock file
   at `.owl/local/task-<id>.lock`.

5. **Return-typing / release / lock-file location — OK.** The block returns
   `Result.ok(:removed)` (an `Owl::Result::Ok`), so `removed.err?` is `false` on
   the success path and `true` on the acquire-failure path — one `return removed if
   removed.err?` correctly covers both. The lock token is released in
   `with_lock`'s `ensure` (task_mutation_lock.rb:50-52). The lock file resolves to
   the `local_state` role (`Locks::Backends::Filesystem` → `FileLock`, path
   `<root>/.owl/local/task-<id>.lock`), OUTSIDE `task_dir`, so `rm_rf` of the task
   dir does not remove it and the `ensure` release succeeds — confirmed by my
   smoke glob.

6. **Regression + version + CHANGELOG + public contract — OK.** Existing delete
   specs stay green (physically removes dir, rebuilds index, deletes
   abandoned/unknown). My independent smoke confirms an uncontended delete still
   removes the dir, scrubs dangling `blocked_by`, rebuilds the index and resets
   the claim. `Tasks::Api.delete(root:, task_id:)` (api.rb:208) and
   `backends/filesystem.delete_task` (filesystem.rb:174-175) are UNCHANGED — the
   `locks:/clock:/sleeper:` injection is a back-compat add on
   `Internal::Deleter.call` only, defaulted to production collaborators, used
   solely by the new spec. So the CLI/JSON/public contract is intact. The
   public-API 100%-line SimpleCov gate did not trip (rspec exit 0), so
   `**/api.rb` coverage holds; `deleter.rb` is internal and not subject to the
   100% gate (its `lock_held` err branch is exercised by the new spec anyway).
   version 0.18.0→0.19.0 (minor) with an accurate `[0.19.0]` CHANGELOG entry.

# Resolution

Accepted. The fix is minimal and correct: exactly the `rm_rf` is serialized
against same-task mutators under the deleted task's own lock, while the
cross-task `clean_dangling_refs` and the index rebuild stay outside it so no
two-lock cycle between parallel deletes is possible. The `task_not_found` check
precedes the lock, the `lock_held` fail-safe propagates without deleting, the
lock file lives outside the doomed directory and releases in `ensure`, and the
public API surface is untouched. Full suite + RuboCop green, README undisturbed,
version/CHANGELOG correct, and an independent (non-author) smoke reproduces both
the happy path and the `lock_held`-leaves-dir-intact path. No changes required.

# Remediation

n/a — no defects found.

# Residual risks

- **TOCTOU between the existence check and the lock (benign).** `task_not_found`
  is decided before `remove_dir_locked`; if another delete of the SAME task wins
  the lock and removes the dir in between, this caller still acquires the lock and
  `rm_rf`s an already-gone path (idempotent no-op), then reports `removed: true`.
  Harmless — no crash, no deadlock — but the success Result can over-claim
  ownership of a removal another process performed. Out of scope for this task.
- **Version bump is judgment, not wrong.** 0.18.0→0.19.0 (minor) is defensible
  and consistent with TASK-0035 treating the locking work as feature-level; a
  back-compat hardening like this could equally have been a patch. Not a blocker.
- **`clean_dangling_refs` still uses default lock collaborators.** The
  `locks:/clock:/sleeper:` injection is threaded only into `remove_dir_locked`;
  `clean_dangling_refs` calls `with_lock` with production defaults. Fine in
  practice (and keeps the deadlock-avoidance argument simple), but the
  dangling-ref locking is not unit-injectable. Cosmetic, not a defect.
- **Acquire deadline surfaces `:lock_held` rather than blocking forever**
  (inherited from TaskMutationLock / IndexWriter): a pathologically long-held
  foreign lock past the 10s deadline returns a recoverable error rather than
  waiting — correct fail-safe, but the CLI must keep surfacing it intelligibly.
