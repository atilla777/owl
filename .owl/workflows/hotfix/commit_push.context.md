---
step_id: "commit_push"
applies_to_session_type: "execution"
intended_audience: "subagent"
summary: "Commit the task changes and push the branch (hotfix workflow, no archive)."
---

# Purpose

Stage every change made during this workflow (code, tests, the task's
`brief`, `verification`, and `review`) and create one commit on the current
branch, then push to the remote. This is the final, externally-visible step.

## When to use

After `review_code` in the `hotfix` workflow. Note: `hotfix` has **no
`archive` step**, so the task directory stays under `tasks/<TASK-ID>/`
and is committed there (not moved to `tasks/archive/`). Archive it later
by hand with `owl archive TASK-ID` if desired.

## Inputs

- Working tree with all task-scoped changes.
- Project commit/push conventions — typically supplied via project
  overlay (`.owl/overlays/commit_push.md` or `docs/ai/commit_push.md`).

## Sequence

This step's side effect *is* the commit, and it is delivered by a single
atomic command:

```
owl commit-push TASK-ID --message "Owl: <concise description>"
```

`owl commit-push` runs the whole sequence as one transaction: `git add -A`
→ flip `commit_push: done` in `task.yaml` → `git add -A` again (so the
flip rides the same commit) → take the repo-scoped `git` push lock →
`git commit` → `git pull --rebase` → `git push` → release the lock. No
separate `owl step complete`, no double manual `git add`, and no
"sync … step state to done" follow-up commit are needed; the working tree
is left clean. (`hotfix` has no `archive` step, so the committed task
directory stays under `tasks/<TASK-ID>/`.)

Before calling it, do the preconditions from the project overlay: review
`git status` for stray or suspicious files and confirm the push target. If
anything looks wrong, stop and report instead of running the command.

Failure handling is built in:

- Any failure **before** `git commit` leaves `commit_push` `running` with
  no commit.
- A successful commit whose `git pull --rebase`/`git push` fails keeps the
  local commit (already carrying `commit_push: done`) and returns
  `push_retryable`; re-run the **same** command to retry only pull + push,
  never a second commit.
- `rebase_conflict` and `lock_held` are returned structurally for a human
  decision — do **not** `--steal` the lock.

Then write the report (`owl step report ... --body -`). Reports live under
`.owl/local/` (gitignored), so this does not dirty the tree.

## Mode

Autonomous. Use the message format and remote/branch policy from the
project overlay. In the Owl bootstrap project the policy is "push to
`main` directly, no PR ceremony"; other projects should override this in
their overlay.
