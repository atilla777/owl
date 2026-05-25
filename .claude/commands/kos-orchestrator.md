---
description: Continue or claim KOS work through the API-first orchestrator
---
Load skill `kos-orchestrator`.

Use the command arguments as workflow intent: $ARGUMENTS

Rules:
- if there are no arguments, continue or claim the next actionable KOS task through the KOS API
- if the arguments mean creating or brainstorming a new task, dispatch to the canonical brainstorm flow
- if the intent is ambiguous, ask whether to continue current KOS work or start a new KOS task

Follow the skill instructions exactly. Treat KOS application state as authoritative for task selection, workflow status, specs, artifacts, git trace, and completion reports. Do not use legacy repository Markdown (`AGENTS.md`, `ROADMAP.md`, `REQUIREMENTS.md`, `ARCHITECTURE.md`, `docs/historical/2026-05-implementation-plan.md`) as active workflow state.
