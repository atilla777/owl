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

## Mode

Autonomous. Use the message format and remote/branch policy from the
project overlay. In the Owl bootstrap project the policy is "push to
`main` directly, no PR ceremony"; other projects should override this
in their overlay.
