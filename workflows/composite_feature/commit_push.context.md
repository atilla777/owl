# Purpose

Stage every change produced by this composite (code from each child,
tests, docs, archived parent + child task files) and create one commit
on the current branch, then push to the remote. This is the final,
externally-visible step.

## When to use

After `archive` in the `composite_feature` workflow.

## Inputs

- Working tree with all task-scoped changes from parent + every child
  (post-archive).
- Project commit/push conventions — typically supplied via project
  overlay (`.owl/overlays/commit_push.md` or `docs/ai/commit_push.md`).

## Outputs

- One commit containing the implementation from every child, tests,
  published docs, and the archived parent + child task files.
- `git push` to the configured remote.

## Mode

Autonomous. Use the message format and remote/branch policy from the
project overlay.
