---
description: Load the owl-cli skill for canonical bin/owl usage.
---
Load skill `owl-cli`.

Use the command arguments as command intent (subcommand hint, TASK-ID, free-form): $ARGUMENTS

Rules:
- never read `.owl/` or `tasks/` directly — go through `owl ...` CLI.
- prefer `--json` for read operations; iterate the documented response shapes.
