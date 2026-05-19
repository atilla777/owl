# Purpose

Collect each child task's `verification.md`, summarize outcomes, and produce the
parent task's `verification` artifact.

## When to use

Inside `composite_feature` after `coordinate` confirms all children are verified.

## Inputs

- Each child task's `verification` artifact.

## Outputs

- `verification` artifact for the parent (composite) task with rolled-up commands and outcomes.
