---
step_id: "brief"
applies_to_session_type: "discussion"
applies_to_variants: ["root_cause"]
intended_audience: "orchestrator"
summary: "Find bug root cause (root_cause variant)."
---

# Purpose

Capture a bug-driven brief: record the observed symptoms, a reliable
reproduction, the underlying **root cause**, and acceptance criteria
that confirm the fix. Downstream `design`, `plan`, and `implement` will
target the root cause — not just the symptom.

## When to use

Invoked when `brief` runs with `variant: root_cause` (e.g.
`owl task create --workflow feature --variant brief=root_cause` for a
bug report).

## Inputs

- Task id (from `owl task current --json` or explicit argument).
- The original bug report: ticket, Sentry link, user description, logs,
  stack traces, anything the reporter sent.

## Outputs

- `brief` artifact at `tasks/<TASK-ID>/brief.md` with front matter
  `status: approved` and `variant: root_cause`, structured as:

  - **Symptoms** — what the user/system observes (error message, wrong
    output, missing behavior). Keep it concrete.
  - **Reproduction** — minimal steps to trigger the bug, including any
    state preconditions and the expected vs. actual outcome.
  - **Root cause** — the deepest understood reason. If still unknown,
    say so explicitly and list ruled-out hypotheses.
  - **Acceptance criteria** — observable conditions that prove the bug
    is fixed (specific assertions, not "works again").

## Mode

Interactive. Push back when the report only describes symptoms — keep
asking diagnostic questions until either the root cause is named or
the brief explicitly states "root cause unknown" with a planned next
diagnostic step. Questions follow the Owl skill conventions (numbered
options).
