---
step_id: "merge_docs"
applies_to_session_type: "execution"
intended_audience: "subagent"
summary: "Merge published docs into the repository."
---

# Purpose

Apply the `design` artifact to project documentation under `docs/` per
the workflow's `publishes` rules, and flip the design's front matter
status to `shipped`.

## When to use

After `review_code` in the `feature` workflow. If `design` was skipped,
this step becomes a no-op (the `owl publish` command returns
`no_publishable_artifacts` and the step is completed without writes).

## Inputs

- Approved `design` artifact.
- Workflow `publishes` rules.

## Outputs

- Files written under `docs/<...>` per `publishes` rules, with
  `.bak-<timestamp>` siblings when an existing file is overwritten.
- `design.md` front matter updated from `approved` to `shipped`.

## Mode

Autonomous. Drive this step with `owl publish TASK-ID --json`. Owl
honors the `publishes` rules declared in the workflow YAML.
