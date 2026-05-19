---
description: Show progress for the current Owl task.
---
Resolve the current task and report progress.

1. `owl task current --json` to get TASK-ID (or use $ARGUMENTS if a TASK-ID is supplied).
2. `owl status TASK-ID --json` for the agent-friendly summary (steps with `ready` flag, progress done/total/pct, blockers, `children` for composite tasks).

Fall back to `owl task inspect TASK-ID --json` + `owl task ready-steps TASK-ID --json` only when you need the raw underlying payload.

$ARGUMENTS
