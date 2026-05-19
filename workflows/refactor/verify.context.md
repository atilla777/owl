# Purpose

Run tests / smoke / static checks and record the outcome with Summary / Commands /
Outcomes so the next step (publish/archive) can rely on a passing baseline.

## When to use

After `apply` in `feature` / `feature_slice` / `hotfix` / `refactor` workflows.
In `composite_feature` use `aggregate_verify` instead.

## Inputs

- Code changes from `apply`.
- Project verification harness (test suites, linters, smoke scripts).

## Outputs

- `verification` artifact under `tasks/<TASK-ID>/verification.md` with status
(passed/failed/partial) in front matter.
