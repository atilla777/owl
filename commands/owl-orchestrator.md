---
description: Drive an Owl task through its workflow end-to-end.
---
Load skill `owl-orchestrator`.

Use the command arguments as workflow intent (TASK-ID, step hint, or free-form): $ARGUMENTS

Rules:
- if the arguments name a TASK-ID, claim it with `owl task claim TASK-ID --json` (takes the lease, sets current, returns a token) and drive that task.
- if there are no arguments: try `owl task current --json`; on `no_current_task`, auto-select via `owl task available --json` and claim the top candidate with `owl task claim --next --json` (keep the returned token). If nothing is available, report "no runnable planned tasks" — do not surface the raw `no_current_task` error.
- hold the lease `token` in context for the run; the claim auto-clears on archive/abandon, and an unfinished claim expires on its TTL so other sessions can pick the task up.
- never read `.owl/` or `tasks/` directly — go through `owl ...` CLI.
