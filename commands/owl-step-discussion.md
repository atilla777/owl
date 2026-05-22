---
description: Execute a ready Owl workflow step of session_type `discussion` through the owl-step-discussion skill.
---
Load skill `owl-step-discussion`.

Use the command arguments as `TASK-ID` + optional `STEP-ID` (or free-form intent): $ARGUMENTS

Rules:
- if no TASK-ID supplied, resolve it via `owl task current --json`.
- never invent a step id; pick from `owl task ready-steps TASK-ID --json`.
- only dispatch when the chosen step has `session_type: discussion`; abort otherwise.
- never read `.owl/` or `tasks/` directly — go through `owl ...` CLI.
