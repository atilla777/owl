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

## Sequence (IMPORTANT — overrides the generic execution-step order)

This step's side effect *is* the commit, so completion MUST be recorded
**before** the commit. Otherwise `owl step complete` flips this step to
`done` *after* the commit and leaves the archived `task.yaml` dirty in
the working tree. Run the actions in exactly this order:

1. `git add -A` — stage every workflow change (code, tests, published
   docs, archived task files). At this point the archived `task.yaml`
   still shows `commit_push: running`.
2. `owl step complete TASK-ID STEP-ID` — flips this step to `done` in the
   archived `task.yaml` and releases the current-task pointer. (Completing
   an already-`done` step is an idempotent no-op, so a later safety-net
   `complete` from the orchestrator is harmless.)
3. `git add -A` — re-stage so the `commit_push: done` flip from step 2 is
   part of the commit.
4. `git commit` + `git push` — the single publishing commit now captures
   `commit_push: done`; the working tree is left clean.
5. Write the report (`owl step report ... --body -`). Reports live under
   `.owl/local/` (gitignored), so this does not dirty the tree.

Do **not** commit before `owl step complete`; the commit must be the last
mutation of tracked files.

## Mode

Autonomous. Use the message format and remote/branch policy from the
project overlay. In the Owl bootstrap project the policy is "push to
`main` directly, no PR ceremony"; other projects should override this
in their overlay.
