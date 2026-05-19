# Purpose

Move `tasks/<TASK-ID>/` into `tasks/archive/<date>-<TASK-ID>-<slug>/`, update
`tasks/index.yaml`, set the task status to archived.

## When to use

Final step of `feature` / `composite_feature` / `hotfix` workflows. For composite
parents, the archive runs atomically across all children.

## Inputs

- Completed task with all required workflow steps in done/skipped.

## Outputs

- `tasks/<TASK-ID>/` moved into `tasks/archive/<date>-...`, task.yaml
`status: archived`, tasks/index.yaml updated.

## Notes

Drive this step with `owl archive TASK-ID --json`. Composite parents are archived
atomically together with all ready children; if any child is not ready, the command
returns `composite_with_unready_children` and lists the missing steps. Closing this
step (`owl step complete TASK-ID archive`) is a separate user signal from running
`owl archive`.
