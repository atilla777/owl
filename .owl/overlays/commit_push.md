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

Follow the ordered sequence in the built-in step context
(`commit_push.context.md`): stage → `owl step complete` → re-stage →
`owl git lock` → `git commit` → `git pull --rebase` → `git push` →
`owl git unlock`. The completion is recorded **before** the commit so the
archived `task.yaml` lands clean in the same commit.
