---
step_id: "commit_push"
applies_to_session_type: "execution"
intended_audience: "subagent"
summary: "Commit the task changes and push the branch (quick workflow, no archive)."
---

# Purpose

Stage every change made during this workflow (code, tests, the task's
`brief` and `verification`) and create one commit on the current branch,
then push to the remote. This is the final, externally-visible step.

## When to use

After `implement` in the `quick` workflow. Note: `quick` has **no
`archive` step**, so the task directory stays under `tasks/<TASK-ID>/`
and is committed there (not moved to `tasks/archive/`). Archive it later
by hand with `owl archive TASK-ID` if desired.

## Inputs

- Working tree with all task-scoped changes.
- Project commit/push conventions — typically supplied via project
  overlay (`.owl/overlays/commit_push.md` or `docs/ai/commit_push.md`).

## Sequence (IMPORTANT — overrides the generic execution-step order)

This step's side effect *is* the commit, so completion MUST be recorded
**before** the commit; otherwise `owl step complete` flips this step to
`done` after the commit and leaves the task's `task.yaml` dirty in the
working tree. Run the actions in exactly this order:

1. `git add -A` — stage every workflow change (code, tests, the task's
   `brief.md` / `verification.md`, and `task.yaml`).
2. `owl step complete TASK-ID STEP-ID` — flips this step to `done` in
   `task.yaml`. (Completing an already-`done` step is idempotent, so a
   later safety-net `complete` from the orchestrator is harmless.)
3. `git add -A` — re-stage so the `commit_push: done` flip is in the commit.
4. Serialize and publish the push:
   a. `owl git lock --json` — take the repo-scoped push lock; keep the
      returned `token`. On `lock_held` (exit 2) another session is
      mid-push: wait briefly and retry, or stop and report.
   b. `git commit`, then `git pull --rebase` and `git push`.
   c. `owl git unlock --token <token>` — always release (it also
      self-heals after its TTL). Leave the working tree clean.
5. Write the report (`owl step report ... --body -`). Reports live under
   `.owl/local/` (gitignored), so this does not dirty the tree.

Do **not** commit before `owl step complete`; the commit must be the last
mutation of tracked files.

## Mode

Autonomous. Use the message format and remote/branch policy from the
project overlay. In the Owl bootstrap project the policy is "push to
`main` directly, no PR ceremony"; other projects should override this in
their overlay.
