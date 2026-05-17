---
description: Autonomously commit, push, and finalize git trace for a KOS task
---
Load skill `kos-deliver`.

Use the command arguments as delivery intent for the active or specified KOS task: $ARGUMENTS

Follow the skill instructions exactly. Use `kos-repo` to inspect status, stage scoped files, commit, and push when verification and review both pass. Return a git trace payload for KOS persistence; stop on suspicious files, secrets, ambiguous scope, or push concerns.
