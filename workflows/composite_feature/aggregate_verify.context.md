# Purpose

Collect each child task's `verification` artifact, roll up commands
and outcomes, and produce the parent task's `verification` artifact.

## When to use

After `coordinate` in the `composite_feature` workflow, once every
child task has its `review_code` step done or skipped.

## Inputs

- Each child task's `verification` artifact.
- Each child task's `review` artifact (for surfacing any unresolved
  findings at the parent level).

## Outputs

- `verification` artifact at `tasks/<PARENT-ID>/verification.md` with
  `Summary / Commands / Outcomes` aggregated across children and front
  matter status `passed | failed | partial`.

## Mode

Autonomous. If any child verification is `failed`, the parent
aggregate is also `failed` and the user is notified before
`merge_docs` runs.
