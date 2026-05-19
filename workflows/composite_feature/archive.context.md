# Purpose

Move `tasks/<TASK-ID>/` (parent + every ready child) into
`tasks/archive/<date>-<TASK-ID>-<slug>/`, update `tasks/index.yaml`,
and set every archived task's status to `archived`. Runs *before*
`commit_push` so the archived files land in the same commit.

## When to use

After `merge_docs` in the `composite_feature` workflow.

## Inputs

- Completed parent + every child task with every required step in
  `done` or `skipped`.

## Outputs

- Each `tasks/<ID>/` moved to `tasks/archive/<date>-<ID>-<slug>/`.
- Every `task.yaml` status set to `archived`.
- `tasks/index.yaml` updated.

## Mode

Autonomous. Drive this step with `owl archive TASK-ID --json` on the
parent — Owl archives the parent and all ready children atomically. If
any child is not ready, the command returns
`composite_with_unready_children` and lists the missing steps. Closing
this step (`owl step complete TASK-ID archive`) is a separate signal
from running `owl archive`.
