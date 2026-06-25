---
status: resolved
verdict: accepted
summary: "Independent, deadlock-focused review of TASK-0035 — a per-task mutation lock (Owl::Tasks::Internal::TaskMutationLock, repo-scoped Owl::Locks name `task-<id>`, blocking acquire built from the non-blocking primitive with a 10s deadline / 20ms backoff, release in ensure) wrapping every read-modify-write of tasks/<id>/task.yaml to kill the tracker-vs-step lost-update race. I audited all 11 with_lock call-sites and confirmed the #1 invariant: in EVERY wrapped mutator the TaskReader.read AND the subsequent AtomicYamlWriter/TaskWriter.write are BOTH inside the with_lock block — no mutator left its read outside (step status_writer locked_update, task status_writer inline block, label/dependency/abandon/plan_approval/filesystem set_step_variant+write_priority all read-under-lock). #2 No reentrance / self-deadlock: `grep with_lock lib/owl/steps/api.rb` is EMPTY, so complete/reopen/reset/skip/start/mark_running are NOT wrapped at api level — each internal StatusWriter.update / set_step_variant / PlanApproval.clear takes and releases the lock in turn, sequentially, never nested; reopen --cascade loops StatusWriter.update (acquire/release each) then PlanApproval.clear (own lock); complete runs StatusWriter.update (releases) THEN ArchiveFinalizer (takes no lock); start runs set_step_variant (releases) THEN StatusWriter.update. The non-reentrant FileLock is therefore never re-acquired while held for the same task. #3 Lock ordering is strictly task→index: every persist (label/dependency/abandon/task-status) and the deleter call IndexWriter.rebuild (the `index` lock) from INSIDE the task-lock as the innermost leaf; nobody grabs a task-lock while holding the index lock. deleter.clean_dangling_refs scrubs each OTHER task under ITS OWN lock, one at a time (never two held), BEFORE the final IndexWriter.rebuild — not nested. #4 release-in-ensure is honest (test raises and asserts the lock file is gone). #5 the `no lost update on stale read` spec is genuine — a foreign holder commits ['foreign'] via the sleeper while the mutator retries, the in-lock read then observes ['foreign'] and appends 'mine' → %w[foreign mine]; a stale read would have produced ['mine'] and failed. #7 DependencyWriter.add writes only task_id's payload under its lock (depends_on is read-only for existence/cycle). I also ran a REAL 2-thread concurrent smoke (50 distinct labels per thread on one task) → 100/100 survived, zero lost updates. bundle exec rspec → 1979 examples, 0 failures, 1 pre-existing pending, exit 0 (the SimpleCov public-API 100% gate did NOT trip, so **/api.rb coverage holds); README not dirtied (no checkout); rubocop on all 12 touched files → no offenses. version 0.17.2→0.18.0 (minor, new feature) + CHANGELOG entry correct. No defects. Verdict: accepted."
---

# Summary

Independent, adversarial review of TASK-0035 — introduction of a per-task
mutation lock so concurrent mutations of the SAME `tasks/<id>/task.yaml` cannot
lose an update. Tracker operations (set-status, label add/remove, dependency
add/remove, abandon, priority, step-variant, plan approve/clear) deliberately do
NOT take the claim lease, so before this change they could interleave with a
step-status mutation from another session and silently clobber one another
(last-write-wins). The fix wraps each mutator's whole read-modify-write in
`Owl::Tasks::Internal::TaskMutationLock.with_lock(root:, task_id:)`, a
file-lock named `task-<id>` via `Owl::Locks`, modelled exactly on
`IndexWriter` (non-blocking acquire retried to a 10s deadline with 20ms
backoff, release in `ensure`).

Because this is a concurrency change I treated deadlock, reentrance and
lost-update as the primary failure modes and verified each against the code, the
unit tests, AND a real multi-threaded smoke. No defects found. Verdict:
**accepted**.

Production changes reviewed:
- `lib/owl/tasks/internal/task_mutation_lock.rb` — NEW lock module.
- `lib/owl/steps/internal/status_writer.rb` — `update` wraps `locked_update`;
  gains `root:`.
- `lib/owl/steps/api.rb` — threads `root:` into every `StatusWriter.update`
  call and into `PlanApproval.clear`; NO api-level `with_lock`.
- `lib/owl/tasks/internal/child_creator.rb` — passes `root:` to `StatusWriter.update`.
- `lib/owl/tasks/backends/filesystem.rb` — `set_step_variant` + `write_priority`
  wrap their locked bodies.
- `lib/owl/tasks/internal/{status_writer,label_writer,dependency_writer,abandon_writer,plan_approval,deleter}.rb`
  — each read-modify-write wrapped; `plan_approval.clear` re-signatured from
  `tasks_root:` to `root:`.
- `lib/owl/version.rb` 0.17.2→0.18.0, `CHANGELOG.md` `[0.18.0]`.
- `spec/owl/tasks/internal/task_mutation_lock_spec.rb` — NEW.

# Findings

All eight review-focus points checked against code, the lock model
(`IndexWriter`), the test run, and a live concurrent smoke. Each confirmed.

1. **Read-under-lock in every mutator — OK (the load-bearing invariant).** I
   read all 11 `with_lock` call-sites and confirmed both the `TaskReader.read`
   and the `AtomicYamlWriter`/`TaskWriter.write` sit INSIDE the block:
   - step `status_writer.rb` — `locked_update` (read+write) is the whole body of
     the block.
   - task `status_writer.rb` — `read` and `write_status` (which writes) are both
     inside the inline `with_lock do … end`.
   - `label_writer.rb` — `locked_mutate` reads then `persist`-writes inside.
   - `dependency_writer.rb` — `locked_add`/`locked_remove`: `read_pair`/`read`
     then `persist` all inside; the cycle guard reads the index (read-only) inside.
   - `abandon_writer.rb` — `locked_call` reads then writes+persist inside.
   - `plan_approval.rb` — `locked_approve` reads then `finalize_approval`-writes
     inside; `locked_clear` reads then `TaskWriter.write` inside.
   - `filesystem.rb` — `locked_set_step_variant` and `locked_write_priority`
     each read then write inside.
   No mutator was left with its read OUTSIDE the lock and only the write inside —
   the stale-read window is closed everywhere.

2. **No reentrance / self-deadlock — OK.** `grep -n with_lock lib/owl/steps/api.rb`
   is **EMPTY**: none of `start/complete/reopen/reset/skip/mark_running` is
   wrapped at the api level, so they cannot hold a `task-<id>` lock across two
   internal mutators. Each internal call acquires and releases on its own:
   - `complete`: `StatusWriter.update` (acquire→write→release) THEN
     `ArchiveFinalizer.call`, which takes NO lock (it only reads task.yaml and
     resets the current-pointer) — sequential, not nested.
   - `reopen --cascade`: the `targets.each` loop calls `StatusWriter.update`
     once per target step, each taking and dropping the lock in turn; AFTER the
     loop `PlanApproval.clear` takes its own lock. Strictly sequential — no
     nesting, so the non-reentrant FileLock never blocks on itself.
   - `start(variant:)`: `set_step_variant` (acquire→write→release) THEN
     `StatusWriter.update` (acquire→write→release) — sequential.
   `idempotent_complete` writes nothing (only `ArchiveFinalizer`), so it never
   takes the lock at all. Confirmed there is no path where a wrapped block
   re-invokes a same-task mutator.

3. **Lock ordering task→index, no inverse — OK.** Every `persist` that touches
   the index (`label_writer`, `dependency_writer`, `abandon_writer`, task
   `status_writer`) calls `IndexWriter.rebuild` (the `index` lock) from INSIDE
   the task-lock, making `index` the innermost leaf — matching the documented
   `task-lock -> index-lock` order. No call-site acquires a task-lock while
   already holding the index lock (IndexWriter's body is a pure scan+write that
   calls nothing back into task locks). `deleter.clean_dangling_refs` scrubs each
   OTHER live task under ITS OWN `task-<id>` lock, one child at a time inside the
   loop (release in `ensure` each iteration, never two held), and the single
   `IndexWriter.rebuild` runs AFTER the loop returns — so the per-task locks are
   already released before the index lock is taken. No cross-task lock is held
   while taking another, so no lock-cycle/deadlock is possible.

4. **release-in-ensure — OK, honestly tested.** `with_lock` releases the token in
   an `ensure`, and the spec `releases the lock even when the block raises`
   raises `RuntimeError, 'boom'` from the block and asserts the lock file is
   gone — a genuine exception-path assertion, not a happy-path stand-in.

5. **Lost-update test is genuine — OK.** `serialization (no lost update on stale
   read)` is not a fake: a foreign holder acquires `task-TASK-0001`, and while
   the mutator is retrying the injected `sleeper` (a) reads, (b) commits
   `labels: ['foreign']`, then (c) releases the lock. The mutator then acquires,
   reads — observing `['foreign']`, NOT the pre-contention `[]` — appends
   `'mine'`, and writes. Final == `%w[foreign mine]`. Had the read been stale the
   result would be `['mine']` and the test would fail, so it truly proves the
   in-lock read sees the prior writer's committed state.

6. **Single-threaded regression — OK.** Full suite green (1979 examples, 0
   failures) including every pre-existing mutator/step/tracker spec; the lock is
   acquired and dropped instantly with no contender, so uncontended behavior is
   unchanged. RuboCop clean on all touched files.

7. **Cross-task correctness — OK.** `DependencyWriter.locked_add` writes only
   `task_id`'s `blocked_by` (the edge is stored on the dependent), under
   `task_id`'s lock; `depends_on` is read solely to verify existence
   (`read_pair`) and for the acyclicity guard (index read) — it is never
   written. So no foreign task's payload is mutated outside its own lock.

8. **Version + CHANGELOG — OK.** minor 0.17.2→0.18.0 is correct: a new
   serialization feature, back-compatible (no on-disk format / CLI / JSON
   contract change). The `[0.18.0]` entry accurately describes the lock, the
   `task-lock -> index-lock` ordering, the non-reentrant-FileLock caveat, and the
   unchanged single-threaded behavior. The public-API 100%-line-coverage gate
   (`spec_helper` `at_exit`) did not trip — rspec exited 0 — so `steps/api.rb`
   (whose call-sites gained `root:`) retains full coverage.

# Resolution

Accepted. The lock is a faithful copy of the proven `IndexWriter` pattern, every
read-modify-write reads-under-lock, there is no api-level wrapping (so no
reentrant self-deadlock), the only nested lock chain is the safe innermost
`index` lock, and cross-task writes stay within their own lock. A real 2-thread
concurrent smoke (50 distinct labels per thread, 100/100 survived) plus the
honest serialization unit test demonstrate the lost-update race is closed. Full
suite + RuboCop green, README undisturbed, version/CHANGELOG correct. No changes
required.

# Remediation

n/a — no defects found.

# Residual risks

- **Delete-vs-mutate on the deleted task itself.** `Deleter.call` `rm_rf`s the
  target task dir WITHOUT taking that task's own `task-<id>` lock (it only locks
  the OTHER tasks it scrubs). A session mutating the task at the exact instant of
  deletion could race the removal (the mutator's atomic write could resurrect a
  file under a half-deleted dir, then the index rebuild ignores it). This is the
  inherent delete-while-in-use hazard, low severity, and out of this task's
  stated scope (lost-update among concurrent mutations of a LIVE task); worth a
  follow-up if delete concurrency becomes real.
- **Acquire deadline surfaces `:lock_held` rather than blocking forever.** A
  pathologically long-held foreign lock (or a stale lock file past TTL handling)
  past the 10s deadline returns a recoverable `:lock_held` error to the caller
  rather than waiting — correct fail-safe behavior, but callers/CLI must surface
  it intelligibly; same trade-off the existing `IndexWriter` already makes.
- **Step-status writes still do not refresh the index** (pre-existing): the step
  `status_writer` writes task.yaml but calls no `IndexWriter`, so step-status
  changes are not mirrored into `index.yaml`. Unchanged by this task and not a
  lock concern, but noted for completeness.
