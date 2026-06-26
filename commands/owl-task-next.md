---
description: Do the next ready step for the current Owl task.
---
Pick the next ready step and run it via `/owl-orchestrator`.

1. `owl task current --json` to get the current TASK-ID (use $ARGUMENTS to override).
2. `owl next [TASK-ID] --json` — the canonical next-action advisor; it returns the step to run as `action.dispatch_step.step_id` (do not pick the first ready step by hand).
3. Dispatch to `/owl-orchestrator` with that TASK-ID + step hint; the orchestrator delegates to `owl-step-discussion` / `owl-step-execution` by `session_type`.

$ARGUMENTS
