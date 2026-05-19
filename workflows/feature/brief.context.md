# Purpose

Capture the brief for a new task: turn a rough request into a structured
`Problem / Goal / Scenarios / Edge cases / Acceptance criteria` document
so every downstream step works from one record of intent.

## When to use

First step of `feature` and `composite_feature` workflows.

## Inputs

- Task id (from `owl task current --json` or explicit argument).
- The user's request: chat history, ticket, requirements paste, sketches.

## Outputs

- `brief` artifact at `tasks/<TASK-ID>/brief.md` with front matter
  `status: approved` once the user confirms the captured intent.

## Mode

Interactive. Ask clarifying questions about ambiguous scenarios, missing
edge cases, and acceptance criteria the user has not stated explicitly.
Questions follow the Owl skill conventions (numbered options).
