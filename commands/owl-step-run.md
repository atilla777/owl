---
description: Execute any ready Owl workflow step through the universal owl-step-run skill.
---
Load skill `owl-step-run`.

Use the command arguments as `TASK-ID` + optional `STEP-ID` (or free-form intent): $ARGUMENTS

Rules:
- if no TASK-ID supplied, resolve it via `owl task current --json`.
- never invent a step id; pick from `owl task ready-steps TASK-ID --json`.
- never read `.owl/` or `tasks/` directly — go through `owl ...` CLI.
