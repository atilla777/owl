---
status: resolved
verdict: accepted
summary: "owl commit-push now stages scoped: the delivery commit excludes the tasks/<id>/ dirs of OTHER active tasks via `git add -A -- . :(exclude)tasks/<id>` magic pathspecs, and the empty-delivery guard + idempotent-retry invariants moved from whole-tree (`git status --porcelain`) to staged-index probing (`git diff --cached --quiet`) so an untracked task backlog no longer masks a real no-op or a legitimate retry. Verified adversarially on real git: scoped pathspec keeps lib/x.rb + other-task dir staged while excluding the named task dir, with no prefix collision (TASK-001 does not eat TASK-0010); index_dirty? semantics are NOT inverted (ok=true ⇔ empty index, so index_empty? == index_dirty?.ok); Tasks::Api.list returns String-keyed hashes so task['id'] resolves; other_active_task_dirs keeps the current task, drops blank/non-Hash ids, degrades to [] on err. Full suite 1972 examples / 0 failures / 1 pre-existing pending, exit 0; commit_push/api.rb at 100% line coverage (gate); rubocop net-zero on all six touched files. minor bump 0.16.1→0.17.0 + CHANGELOG with the documented known limitation. Verdict: accepted."
---

# Summary

Independent, adversarial review of TASK-0032 — making `owl commit-push` staging
*scoped*. The delivery commit must no longer sweep the `tasks/<id>/` backlog
directories of *other* active tasks into the commit, and the two transaction
invariants (empty-delivery `nothing_to_commit` guard; idempotent post-push
retry) must survive an untracked backlog (`?? tasks/TASK-*`) left in the working
tree, which previously broke the old whole-tree `git status --porcelain` checks.

I re-derived every focus point from the code, exercised the real `git`
pathspec/index behaviour in throwaway repos (not mocks), confirmed the Ruby
key-type assumption the exclude computation depends on, and ran the full suite +
RuboCop + per-file coverage. No defects found. Verdict: **accepted**.

Production changes reviewed:
- `lib/owl/commit_push/internal/git_runner.rb` — new `add_scoped(root:, exclude:)`
  (early-returns to `git add -A` on nil/empty exclude; otherwise emits one argv
  element per `:(exclude)<path>` pathspec, no shell) and `index_dirty?(root:)`
  (`git diff --cached --quiet`).
- `lib/owl/commit_push/internal/transaction.rb` — `call`/`publish`/`flip_done`/
  `stage_and_guard` thread `exclude:`; staging/restaging via `add_scoped`; guard
  and `retry?` keyed on the new `index_empty?` (built on `index_dirty?.ok`);
  `clean_tree?`/`status_porcelain` no longer called.
- `lib/owl/commit_push/api.rb` — `commit_push` computes
  `other_active_task_dirs` (`Tasks::Api.list` minus the current task → `tasks/<id>`)
  and passes it as `exclude:`.
- `lib/owl/version.rb` 0.16.1→0.17.0, `CHANGELOG.md` `[0.17.0]`.
- Specs: new `spec/owl/commit_push/git_runner_spec.rb` (real git), updated
  `api_spec.rb` and `locking_spec.rb`.

# Findings

All seven review-focus points checked; each confirmed by code and/or a real-git
probe and/or a test.

1. **Scoped pathspec is correct — OK (high-priority #1).** Verified on a real
   `git init` repo in `mktemp -d`: with files in `tasks/TASK-AAA/`,
   `tasks/TASK-BBB/`, `lib/x.rb`, running
   `git add -A -- . :(exclude)tasks/TASK-BBB` staged exactly `lib/x.rb` and
   `tasks/TASK-AAA/a.txt` and **not** `tasks/TASK-BBB/b.txt`. The
   `git_runner_spec.rb` `keeps the excluded task dirs out of the index` example
   asserts the same against real git with two exclusions. Adversarial extra: a
   prefix-collision probe (`:(exclude)tasks/TASK-001` against a sibling
   `tasks/TASK-0010/`) confirmed git pathspecs match on path-component
   boundaries — `TASK-0010` stays staged, so no over-exclusion. Each pathspec is
   its own argv element, so there is no shell-glob/word-split exposure.

2. **Back-compat at empty exclude — OK (#2).** `add_scoped` early-returns
   `run(%w[git add -A], root)` when `exclude.nil? || exclude.empty?`, i.e. the
   exact prior `add_all` command. Confirmed on real git (empty exclude stages
   every dir including `tasks/TASK-BBB`) and by two specs (empty + nil exclude).
   The empty-exclude case is reached whenever `other_active_task_dirs` returns
   `[]` (only the current task active, or a failed listing).

3. **Index invariants are NOT inverted — OK (high-priority #3).** Verified the
   exit-code semantics on real git: `git diff --cached --quiet` exits **1**
   (Outcome `ok=false`) when the index has staged changes, and **0**
   (`ok=true`) when the index is empty. Therefore `index_empty?(git, root) ==
   git.index_dirty?(root:).ok` is `true` ⇔ the index is empty. The guard
   (`return nothing_to_commit if index_empty?`) thus fires only on an empty
   index — a real no-op delivery — not on a populated one; and `retry?` requires
   `index_empty?` (index drained because the delivery was already committed) in
   conjunction with `step done` + `unpushed`. The naming reads slightly against
   the grain (the runner method is `index_dirty?` yet `ok=true` means *not*
   dirty), but it is explicitly documented at both the runner and the caller,
   and every facade method already returns `ok = status.success?` for the caller
   to interpret. Behaviour is correct; flagged only as a naming nit, not a
   defect.

4. **Exclude computation — OK (#4).** Confirmed `Tasks::Api.list(root:)` returns
   `value[:tasks]` as an `Array` of **String-keyed** Hashes (source: YAML
   `safe_load` of `tasks/index.yaml` via `IndexReader`, which never symbolizes),
   so `task['id']` resolves rather than silently returning `nil` and nuking the
   whole feature. Probed live: `other_active_task_dirs(root, 'TASK-0032')` → `[]`
   (only the current task active, correctly kept), and for a non-current id →
   `['tasks/TASK-0032']`. `filter_map` drops non-Hash entries; `reject` drops
   empty ids and the current `task_id` (string-compared via `.to_s`); `list.err?`
   degrades to `[]`. All four boundary cases are pinned by specs (multi-task
   exclusion, single-current → `[]`, listing err → `[]`, blank/`'garbage'` →
   filtered).

5. **Happy path + idempotent retry without backlog — OK (#5).** First-run path
   still does `add_scoped` (×2: pre-lock stage + post-flip restage — asserted
   `.twice`), `nothing_to_commit`, `complete`, `commit`, `pull --rebase`,
   `push`, single commit. Commit-failure rollback to `running`, `push_retryable`
   (commit kept), and `rebase_conflict` paths all still pass. The retry branch
   still skips staging/commit/complete and only re-attempts pull+push. With no
   other active task, `exclude=[]` so the on-disk behaviour is byte-identical to
   pre-change.

6. **Layering / dead code — OK (#6).** Other active tasks are read through
   `Owl::Tasks::Api` (added `require_relative '../tasks/api'`), not via direct FS
   access from `commit_push` — respects the architecture rule. `clean_tree?` was
   removed from `transaction.rb`. Note (non-blocking): `GitRunner#status_porcelain`
   and `GitRunner#add_all` are now unreferenced by production code (lines show
   0 coverage); they are public facade methods and the brief explicitly says not
   to delete runner publics gratuitously, so leaving them is acceptable — logged
   as a residual cleanup, not a defect.

7. **Version + CHANGELOG — OK (#7).** 0.16.1→0.17.0 is the right bump: new
   observable staging behaviour is a feature (minor), and the API/CLI/on-disk
   contract is unchanged (`commit_push`'s external signature is untouched; the
   exclude is computed internally). `CHANGELOG.md` `[0.17.0]` documents the
   scoped staging, the index-probe invariant change, **and** the known
   limitation that other tasks' code living *outside* `tasks/` still rides into
   the commit. `lib/owl/commit_push/api.rb` is at 100% line coverage, satisfying
   the public-API gate.

# Resolution

Accepted. The implementation matches the brief, the scoped-pathspec and
index-probe semantics are correct on real git (independently reproduced, not
just mocked), the exclude computation rests on a verified String-key assumption,
back-compat is preserved when no other task is active, and the full suite +
RuboCop + the per-file coverage gate are green. No changes required.

# Residual risks

- **Naming nit:** `GitRunner#index_dirty?` returns `ok=true` when the index is
  *empty* (not dirty). Documented at both ends and behaviourally correct, but a
  future reader could misread it; a rename to e.g. `index_empty?` (ok ⇔ empty)
  would remove the foot-gun. Non-blocking.
- **Dead facade methods:** `status_porcelain` and `add_all` are now unused (0
  coverage). Harmless, but a later sweep could drop them.
- **Documented known limitation:** code changes belonging to other tasks that
  live outside `tasks/` are still swept into the delivery commit — inherent to
  attributing arbitrary code to a task, and called out in the CHANGELOG.
