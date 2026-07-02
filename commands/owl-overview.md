---
description: Render an ASCII task tree (hierarchy, status, deps, current task) for the whole forest or one TASK-ID subtree.
---
Render the Owl task-tree overview for the supplied target.

1. Pass `$ARGUMENTS` to `bin/owl overview` verbatim. Supported forms:
   - `bin/owl overview` — ASCII tree of all non-terminal tasks (archived/abandoned hidden).
   - `bin/owl overview TASK-XXXX` — only that task's subtree.
   - `bin/owl overview --compact` — compact node (marker, id, title only).
   - `bin/owl overview --all` — include archived/abandoned tasks.
   - `bin/owl overview --json` — structured `{ok, tree, current_task_id, warnings}` payload.
2. Print stdout as-is. Surface stderr only when the exit code is non-zero.

$ARGUMENTS
