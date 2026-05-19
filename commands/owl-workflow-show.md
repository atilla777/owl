---
description: Render an Owl workflow as an ASCII diagram (live by TASK-ID, abstract by --workflow KEY).
---
Render the workflow diagram for the supplied target.

1. Pass `$ARGUMENTS` to `bin/owl workflow show` verbatim. Supported forms:
   - `bin/owl workflow show TASK-XXXX` — live ASCII diagram for the given task.
   - `bin/owl workflow show --workflow KEY` — abstract ASCII diagram for a workflow definition.
   - `bin/owl workflow show TASK-XXXX --json` — structured live payload.
   - `bin/owl workflow show --workflow KEY --json` — structured abstract payload.
2. Print stdout as-is. Surface stderr only when the exit code is non-zero.

$ARGUMENTS
