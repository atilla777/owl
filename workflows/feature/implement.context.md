---
step_id: "implement"
applies_to_session_type: "execution"
intended_audience: "subagent"
summary: "Execute the plan checklist — write code and tests together."
---

# Purpose

Execute the `plan` checklist — write production code and tests together
and run your own iterative checks as you go. This is the build step: it
creates no artifact. The authoritative, objective verification happens
later at `review_code`, where Owl itself runs the configured command and
authors the `verification` artifact — your in-progress runs here are your
own working signal, not the gate.

## When to use

After `plan` in the `feature` workflow.

## Inputs

- `plan` artifact (the checklist).
- `brief` and `design` for the intent and API surface.
- Project test/lint/smoke commands (project overlay can list them).

## Outputs

- Repository changes scoped to the task. (No artifact is recorded by this
  step.)

## Mode

Autonomous. Write tests alongside production code (test-first preferred).
Run the suite locally as often as you like to drive the work; leave the
authoritative verification to `review_code`. Stop and escalate only on a
real blocker.
