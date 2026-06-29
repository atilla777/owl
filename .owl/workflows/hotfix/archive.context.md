---
step_id: "archive"
applies_to_session_type: "execution"
intended_audience: "subagent"
summary: "Archive the completed task."
---

# Purpose

Move `tasks/<TASK-ID>/` into `tasks/archive/<date>-<TASK-ID>-<slug>/`,
update `tasks/index.yaml`, and set the task status to `archived`. This
runs *before* `commit_push` so the archived files land in the same
commit as the code and docs changes.

## When to use

After `merge_docs` in the `feature` and `composite_feature` workflows.
For composite parents, archive runs atomically across all children.

## Inputs

- Completed task with every required workflow step in `done` or
  `skipped` status.

## Outputs

- `tasks/<TASK-ID>/` moved to `tasks/archive/<date>-<TASK-ID>-<slug>/`.
- `task.yaml` status set to `archived`.
- `tasks/index.yaml` updated.

## Mode

Autonomous. Drive this step with `owl archive TASK-ID --json`.
Composite parents archive atomically together with all ready children;
if any prerequisite step is not ready, the command returns
`workflow_incomplete` and lists the missing steps (via
`details.incomplete_steps`) rather than performing a partial archive. Closing
this step (`owl step complete TASK-ID archive`) is a separate signal
from running `owl archive`.
