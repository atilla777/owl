# Purpose

Copy approved artifacts (typically `spec.md`) to `docs/<...>/` per the workflow
`publishes` rules so domain documentation reflects the latest task.

## When to use

After `verify` (or `aggregate_verify`) in workflows that declare a `publishes` block.

## Inputs

- Verified spec / artifacts referenced by the workflow `publishes` rules.

## Outputs

- Files written under `docs/<...>` per `publishes` rules, with `.backup-<timestamp>`
siblings when overwriting.
- No KOS artifact — the side effect is the docs files.

## Notes

Drive this step with `owl publish TASK-ID --json`. Owl honors the `publishes` rules
declared in the workflow YAML.
