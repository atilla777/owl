---
description: Drive an Owl task through its workflow end-to-end.
---
Load skill `owl-orchestrator`.

Use the command arguments as workflow intent (TASK-ID, step hint, or free-form): $ARGUMENTS

Rules:
- if there are no arguments, continue or claim the current Owl task via `owl task current --json`.
- if the arguments name a TASK-ID, set it current with `owl task use TASK-ID` first.
- never read `.owl/` or `tasks/` directly — go through `owl ...` CLI.
