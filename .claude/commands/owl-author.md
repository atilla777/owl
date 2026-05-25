---
description: Author or edit Owl workflow / artifact-type definitions via Q&A (no direct YAML editing).
---
Load skill `owl-author`.

Use the command arguments as free-form intent (mode, target, id): $ARGUMENTS

Rules:
- never edit `.owl/workflows/*` or `.owl/artifacts/*` directly — go through `owl workflow new|validate|show` and `owl artifact-type new|validate|show`.
- speak `settings.language.communication` (from `owl config show --json`); fall back to English if not set.
- `required_sections` are always English (constitution 5.16) regardless of `settings.language.artifacts`.
