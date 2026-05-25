---
description: Create a new Owl task from a registered workflow.
---
Use `owl task create --workflow <key> --title "..." --json` to create a new task. Pick a workflow from `owl workflow list --json` (typically `feature` for a new feature or fix, `composite_feature` when the work will spawn children). For incident/refactor framings, use `feature` and pick the matching `brief` step variant (`--variant brief=root_cause` or `--variant brief=problem_inventory`) — the legacy `hotfix` and `research` workflows have been folded into those `brief` variants.

After creation, set the task current with `owl task use TASK-ID` and run the orchestrator with `/owl-orchestrator` to start the first step.

Use the command arguments as title / workflow hints: $ARGUMENTS
