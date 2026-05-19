# Purpose

Promote a brief (or the task intent) into a full task specification with
Intent / Acceptance criteria / Non-goals / Open questions / Scope so downstream steps
can plan and apply without re-asking.

## When to use

After `brief` in `feature` / `composite_feature` workflows, or as the first step of
`refactor`.

## Inputs

- `brief` artifact (when the workflow has one).
- Clarifying chat history and any pinned decisions.

## Outputs

- `spec` artifact under `tasks/<TASK-ID>/spec.md` with the required sections and
front matter status approved.
