---
step_id: "plan"
applies_to_session_type: "discussion"
intended_audience: "orchestrator"
summary: "Turn the brief and design into an execution plan."
---

# Purpose

Break the brief's acceptance criteria and the design's API into an
ordered checklist of concrete code changes so `implement` can execute
without re-deciding.

## When to use

After `brief` (and optional `design`) in the `feature` workflow.

## Inputs

- `brief` artifact.
- `design` artifact when the previous step produced one.

## Outputs

- `plan` artifact at `tasks/<TASK-ID>/plan.md` — `Goal` paragraph plus a
  `Checklist` of `- [ ]` items, each naming a file path and the change.

## Mode

Autonomous. Do not ask the user to choose between implementation
options — those choices belong in `design`. Ask only on a real blocker.
