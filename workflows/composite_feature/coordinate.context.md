# Purpose

Track the child task tree, surface readiness / blockers, and signal the orchestrator
when all children are verified and ready for aggregate verification.

## When to use

Inside `composite_feature` after `decompose`.

## Inputs

- Child task tree (`owl task children PARENT-ID --json`, `owl task aggregate-status PARENT-ID --json`).

## Outputs

- Conversational status update; no KOS artifact. Transitions the composite step from
`coordinate` to `aggregate_verify` once children finish their `verify` step.
