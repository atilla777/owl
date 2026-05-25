---
description: Execute a ready Owl workflow step of session_type `execution` through the owl-step-execution skill.
---
Load skill `owl-step-execution`.

Use the command arguments as `TASK-ID` + optional `STEP-ID` (or free-form intent): $ARGUMENTS

Rules:
- if no TASK-ID supplied, resolve it via `owl task current --json`.
- never invent a step id; pick from `owl task ready-steps TASK-ID --json`.
- only dispatch when the chosen step has `session_type: execution`; abort otherwise.
- never prompt the user directly; surface follow-ups in the report's `## Open follow-ups` section.
- emit a markdown-with-frontmatter report via `owl step report --task-id ID --step-id ID --body - --validate`.
- never read `.owl/` or `tasks/` directly — go through `owl ...` CLI.
