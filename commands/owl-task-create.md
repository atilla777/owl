---
description: Create a new Owl task from a registered workflow.
---
Use `owl task create --workflow <key> --title "..." --json` to create a new task. Pick a workflow from `owl workflow list --json` (typically `feature` for a new feature, `hotfix` for an incident, `research` for an investigation, `composite_feature` when the work will spawn children).

After creation, set the task current with `owl task use TASK-ID` and run the orchestrator with `/owl-orchestrator` to start the first step.

Use the command arguments as title / workflow hints: $ARGUMENTS
