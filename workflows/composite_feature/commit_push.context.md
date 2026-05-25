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

## Mode

Autonomous. Use the message format and remote/branch policy from the
project overlay. The parent does **not** include child code in this
commit — each child commits its own implementation through its own
`commit_push` step later.
