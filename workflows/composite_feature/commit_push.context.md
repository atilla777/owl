---
step_id: "commit_push"
applies_to_session_type: "execution"
intended_audience: "subagent"
summary: "Commit composite workflow changes and push the branch."
---

# Purpose

Stage the parent task's own artifacts (brief, design, decomposition,
review) and the spawned child task directories (each holds its
pre-authored `brief.md`), then create one commit and push. This
finalises the parent's contribution to the repository.

## When to use

After `archive` in the `composite_feature` workflow.

## Inputs

- Working tree with the archived parent task directory and the new
  child task directories (each with its `brief.md`).
- Project commit/push conventions — typically supplied via project
  overlay (`.owl/overlays/commit_push.md` or
  `docs/ai/commit_push.md`).

## Outputs

- One commit containing the archived parent + every child task
  directory with its pre-filled brief.
- `git push` to the configured remote.

## Sequence

This step's side effect *is* the commit, and it is delivered by a single
atomic command:

```
owl commit-push TASK-ID --message "Owl: <concise description>"
```

`owl commit-push` runs the whole sequence as one transaction: `git add -A`
(staging the archived parent task directory and every child task
directory) → flip `commit_push: done` in the archived parent `task.yaml`
→ `git add -A` again (so the flip rides the same commit) → take the
repo-scoped `git` push lock → `git commit` → `git pull --rebase` →
`git push` → release the lock. No separate `owl step complete`, no double
manual `git add`, and no "sync … step state to done" follow-up commit are
needed; the working tree is left clean.

Before calling it, do the preconditions from the project overlay: review
`git status` for stray or suspicious files and confirm the push target. If
anything looks wrong, stop and report instead of running the command.

Failure handling is built in:

- Any failure **before** `git commit` leaves `commit_push` `running` and
  creates no commit.
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
project overlay. The parent does **not** include child code in this
commit — each child commits its own implementation through its own
`commit_push` step later.
