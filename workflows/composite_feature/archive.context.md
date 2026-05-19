# Purpose

Move `tasks/<PARENT-ID>/` into
`tasks/archive/<date>-<PARENT-ID>-<slug>/`, update `tasks/index.yaml`,
and set the parent's status to `archived`. Runs *before* `commit_push`
so the archive move lands in the same commit.

## When to use

After `review` in the `composite_feature` workflow.

## Inputs

- Parent task with `brief / design (or skipped) / decomposition /
  review` all in `done` or `skipped`.

## Outputs

- `tasks/<PARENT-ID>/` moved to
  `tasks/archive/<date>-<PARENT-ID>-<slug>/`.
- `task.yaml` status set to `archived`.
- `tasks/index.yaml` updated.

## Mode

Autonomous. Drive this step with `owl archive PARENT-ID --json`.
**Parent archive is a solo operation** — it does not touch child task
directories. Each child archives itself when its own `feature`
workflow reaches its `archive` step. Closing this step
(`owl step complete PARENT-ID archive`) is a separate signal from
running `owl archive`.
