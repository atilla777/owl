---
step_id: "commit_push"
applies_to_session_type: "execution"
intended_audience: "subagent"
summary: "Commit all workflow changes and push the branch."
---

# Purpose

Stage every change made during this workflow (code, tests, docs,
archived task files) and create one commit on the current branch, then
push to the remote. This is the final, externally-visible step.

## When to use

After `archive` in the `feature` and `composite_feature` workflows.

## Inputs

- Working tree with all task-scoped changes (post-archive).
- Project commit/push conventions — typically supplied via project
  overlay (`.owl/overlays/commit_push.md` or `docs/ai/commit_push.md`).

## Outputs

- One commit containing the implementation, tests, published docs, and
  archived task files.
- `git push` to the configured remote.

## Sequence

This step's side effect *is* the commit, and it is delivered by a single
atomic command:

```
owl commit-push TASK-ID --message "Owl: <concise description>"
```

`owl commit-push` runs the whole sequence as one transaction: `git add -A`
→ flip `commit_push: done` in the archived `task.yaml` → `git add -A`
again (so the flip rides the same commit) → take the repo-scoped `git`
push lock → `git commit` → `git pull --rebase` → `git push` → release the
lock. No separate `owl step complete`, no double manual `git add`, and no
"sync … step state to done" follow-up commit are needed; the working tree
is left clean.

Before calling it, do the preconditions from the project overlay: review
`git status` for stray or suspicious files (secrets, unexpected
deletions, large binaries) and confirm the push target. If anything looks
wrong, stop and report instead of running the command.

Failure handling is built in:

- Any failure **before** `git commit` (staging, lock, commit) leaves
  `commit_push` `running` and creates no commit — the delivery is not
  partially applied.
- A successful commit whose `git pull --rebase`/`git push` fails keeps the
  local commit (which already carries `commit_push: done`) and returns
  `push_retryable`. Re-run the **same** `owl commit-push` command: it
  detects the existing commit and only re-attempts pull + push — it never
  creates a second commit.
- `rebase_conflict` (a real merge conflict) and `lock_held` (another live
  session is mid-push) are returned structurally for a human decision —
  do **not** `--steal` the lock.

Then write the report (`owl step report ... --body -`). Reports live under
`.owl/local/` (gitignored), so this does not dirty the tree.

## Mode

Autonomous. Use the message format and remote/branch policy from the
project overlay. In the Owl bootstrap project the policy is "push to
`main` directly, no PR ceremony"; other projects should override this
in their overlay.
