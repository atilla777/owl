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

## Sequence (IMPORTANT — overrides the generic execution-step order)

This step's side effect *is* the commit, so completion MUST be recorded
**before** the commit. Otherwise `owl step complete` flips this step to
`done` *after* the commit and leaves the archived parent `task.yaml` dirty
in the working tree. Run the actions in exactly this order:

1. `git add -A` — stage the archived parent task directory and every child
   task directory. At this point the parent's archived `task.yaml` still
   shows `commit_push: running`.
2. `owl step complete TASK-ID STEP-ID` — flips this step to `done` in the
   archived parent `task.yaml` and releases the current-task pointer.
   (Completing an already-`done` step is an idempotent no-op, so a later
   safety-net `complete` from the orchestrator is harmless.)
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
project overlay. The parent does **not** include child code in this
commit — each child commits its own implementation through its own
`commit_push` step later.
