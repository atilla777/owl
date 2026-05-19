---
description: Do the next ready step for the current Owl task.
---
Pick the next ready step and run it via `/owl-orchestrator`.

1. `owl task current --json` to get the current TASK-ID (use $ARGUMENTS to override).
2. `owl task ready-steps TASK-ID --json` — take the first ready step.
3. Dispatch to `/owl-orchestrator` with that TASK-ID + step hint; the orchestrator delegates to `owl-step-run`.

$ARGUMENTS
