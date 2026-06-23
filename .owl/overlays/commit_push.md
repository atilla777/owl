# Project overlay — `commit_push` step

## Authorization

A ready `commit_push` step **is** the authorization to commit and push.
The workflow graph reached this step only because the user asked the
orchestrator to drive the task end-to-end, and the workflow explicitly
declares `commit_push` as its terminal step. Treat that as the explicit
human approval to write a commit and push it. Do **not** pause to ask for
a separate commit/push confirmation — this overlay overrides the generic
"commit/push needs its own prompt" caution.

This authorization is bounded by the preconditions and stop conditions
below; if any of them is not satisfied, stop and report instead of pushing.

## Remote / branch policy

- Push to `main` **directly**. No feature-branch + PR ceremony for
  Owl-driven deliveries (established project convention).
- One commit per delivery, capturing implementation, tests, published
  docs, and the archived task files.

## Commit message

- First line: `Owl: <concise description of the delivered change>`.
- Match the existing history style (`git log --oneline`); keep the subject
  imperative and under ~72 chars, add a short body only when the change
  needs context.

## Preconditions (stop and report instead of pushing if any fails)

- `git status` shows files unrelated to this task's scope, or anything
  suspicious (secrets, large/binary artifacts, unexpected deletions).
- The push lock (`owl git lock`) cannot be acquired and the holder is not
  known dead — wait/retry briefly, then stop rather than `--steal`.
- `git pull --rebase` surfaces conflicts that need a human decision.
- Any `owl` or `git` command returns an error that one obvious retry does
  not resolve.

## Sequence

Run the whole step as one atomic command:

```
owl commit-push TASK-ID --message "Owl: <concise description>"
```

`owl commit-push` stages every change, flips `commit_push: done` in the
archived `task.yaml`, re-stages so the flip rides the same commit, takes the
repo-scoped `git` push lock, commits, `pull --rebase`es, pushes, and releases
the lock — so no separate `owl step complete`, double `git add`, or
"sync … step state to done" commit is needed.

Perform the **Preconditions** above (review `git status` for stray/suspicious
files; confirm the push target) **before** calling it. Failure handling is
built in: any failure before the commit leaves `commit_push` `running` with no
commit; a successful commit whose push fails keeps the local commit and returns
`push_retryable` — re-run the same command to retry the push idempotently (no
second commit). A `rebase_conflict` or `lock_held` is returned structurally for
a human decision — do not `--steal` the lock.
