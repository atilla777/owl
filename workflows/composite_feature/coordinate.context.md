# Purpose

Track the child task tree, surface readiness or blockers, and signal
the orchestrator when every child has finished its `review_code` step
and is ready for aggregate verification.

## When to use

After `decompose` in the `composite_feature` workflow.

## Inputs

- Child task tree (`owl task children PARENT-ID --json`,
  `owl task aggregate-status PARENT-ID --json`).

## Outputs

- Conversational status update; no artifact. Transitions the parent
  from `coordinate` to `aggregate_verify` once every child has its
  `review_code` step done or skipped.

## Mode

Autonomous. Poll child statuses, surface blockers to the user only
when a child cannot progress without input.
