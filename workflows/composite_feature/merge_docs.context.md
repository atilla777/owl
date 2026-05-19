# Purpose

Apply the parent composite's `design` to project documentation under
`docs/` per the workflow's `publishes` rules, and flip the design's
front matter status to `shipped`.

## When to use

After `aggregate_verify` in the `composite_feature` workflow. If
`design` was skipped, this step becomes a no-op (`owl publish` returns
`no_publishable_artifacts` and the step is completed without writes).

## Inputs

- Approved parent-level `design` artifact.
- Workflow `publishes` rules.

## Outputs

- Files written under `docs/<...>` per `publishes` rules, with
  `.bak-<timestamp>` siblings when an existing file is overwritten.
- `design.md` front matter updated from `approved` to `shipped`.

## Mode

Autonomous. Drive this step with `owl publish TASK-ID --json` on the
parent. Children do not publish individually — only the parent's
cross-cutting design ships to `docs/`.
