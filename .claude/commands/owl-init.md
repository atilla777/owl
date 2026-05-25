---
description: Run the Owl first-run wizard to configure settings (language, storage, optional workflows).
---
Load skill `owl-init`.

Use the command arguments as wizard intent (free-form): $ARGUMENTS

Rules:
- never edit `.owl/config.yaml` directly — go through `owl config set settings.*` for every recorded answer.
- speak English until `settings.language.communication` is recorded; switch to that language afterwards.
- this skill is one-shot bootstrap; for mid-project edits use `bin/owl config set` directly.
