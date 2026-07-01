---
description: Create a new Owl task from a registered workflow.
---
Use `owl task create --workflow <key> --title "..." --json` to create a new task. Pick a workflow from `owl workflow list --json`:

- `feature` (default) — a new feature or fix.
- `composite_feature` — work that will spawn child tasks.
- `hotfix` — an urgent fix; its `brief` step defaults to the `root_cause` variant.
- `refactor` — a refactor; its `brief` step defaults to the `problem_inventory` variant.
- `quick` — a small, well-understood change in a single prompt (no design/plan/review).

You can always override a step variant explicitly (e.g. `--variant brief=root_cause`); `feature` itself carries the `feature`/`root_cause`/`problem_inventory` `brief` variants for incident or refactor framings without switching workflow.

After creation, set the task current with `owl task use TASK-ID` and run the orchestrator with `/owl-orchestrator` to start the first step.

Use the command arguments as title / workflow hints: $ARGUMENTS
