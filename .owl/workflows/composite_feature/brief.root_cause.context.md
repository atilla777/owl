---
step_id: "brief"
applies_to_session_type: "discussion"
applies_to_variants: ["root_cause"]
intended_audience: "orchestrator"
summary: "Find bug root cause for the composite task (root_cause variant)."
---

# Purpose

Capture a bug-driven brief for a **composite** task: a single root
cause that is large enough to need decomposition into multiple child
tasks. Document the symptoms, reproduction, and root cause, then leave
the work-splitting to the upcoming `decompose` step.

## When to use

Invoked when the composite `brief` runs with `variant: root_cause`
(typically: a production incident whose fix spans several
services/areas).

## Inputs

- Task id of the parent composite task.
- The incident report, post-mortem, or root-cause hypothesis.

## Outputs

- `brief` artifact at `tasks/<TASK-ID>/brief.md` with front matter
  `status: approved` and `variant: root_cause`, structured as:

  - **Symptoms** — user/system-visible failures, blast radius.
  - **Reproduction** — minimal way to trigger or observe the failure.
  - **Root cause** — the underlying cause, broad enough to motivate
    multiple child tasks. If still hypothetical, say so.
  - **Acceptance criteria** — the composite-level conditions that
    confirm the incident is resolved (each child will refine its own).

## Mode

Interactive. Aim for a brief broad enough to cover the whole composite
remediation but precise enough that `decompose` can produce
non-overlapping children, each with its own narrower brief. Questions
follow the Owl skill conventions (numbered options).
