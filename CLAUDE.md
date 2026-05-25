# Owl — KOS Bootstrap

This project is connected to KOS. KOS is the authoritative source of agent-operated workflow state: tasks, workflow status, task specs, plans, reviews, completion reports, and git trace live in the KOS application, not in repository Markdown.

## Runtime

- KOS API: `http://127.0.0.1:3000` (override with `KOS_BASE_URL`)
- Actor identity: `KOS_USER_ID` (inherit from `mise.toml`; without it, mutating API calls fail with `Authentication required`)
- Bootstrap (public, no auth): `GET /api/agent_bootstrap`

## Installed KOS Skills

The KOS skill distribution is installed as a self-contained snapshot under `.claude/skills/kos-*`. Matching slash commands live in `.claude/commands/kos-*.md`. Refresh the snapshot from `/home/aleksei/plums/kos/skills/` whenever KOS skills change.

Primary entrypoints:

- `/kos-orchestrator` — continue or claim the next actionable KOS task through the API-first orchestrator. Default for "what should I work on next?" or "continue".
- `/kos-brainstorm` — turn a rough idea into a KOS task and spec.
- `/kos-api` — direct KOS API operations when the orchestrator is not appropriate.
- `/kos-project-memory-import` — one-time migration of repository Markdown memory into KOS knowledge.

Stage commands: `/kos-specify`, `/kos-clarify`, `/kos-analyze`, `/kos-plan`, `/kos-implement`, `/kos-verify`, `/kos-document`, `/kos-review`, `/kos-deliver`, `/kos-completion-report`. Repository helpers: `/kos-repo`.

## Startup Sequence

For any task work, use the smallest API path that gives authoritative state before reading repository Markdown:

1. `Kos::Client#resolve_or_create_current_project` — derive the project from this repo root.
2. `Kos::Client#claim_next_actionable_task` (or `#next_actionable_task` for read-only inspection) — resumes the actor's claimed unfinished task before claiming new work.
3. `Kos::Client#get_task_work_package` — workflow status, blockers, artifacts, specs, history, lock versions.
4. `Kos::Client#get_knowledge_context` — current-stage knowledge bundle; stop if status is unacceptable for the stage.

## Source-Of-Truth Rule

Repository memory has been migrated into KOS knowledge:

- `Owl Project Constitution` (article 23) — `load_policy: required`, `required_project_bootstrap: true`. Loaded automatically before any stage work.
- `Owl product concept: AGENTS.md` (article 24) — full verbatim source.
- `Owl architecture: ARCHITECTURE.md` (article 25) — full verbatim source.
- `Owl requirements: REQUIREMENTS.md` (article 26) — full verbatim source.

The legacy files (`AGENTS.md`, `ARCHITECTURE.md`, `REQUIREMENTS.md`) stay in the repository as historical / human-readable fallback. Do not treat them as active workflow state. Active project memory lives in the KOS knowledge articles above. The implementation-plan snapshot has been archived to `docs/historical/2026-05-implementation-plan.md`.

`docs/historical/2026-05-implementation-plan.md` (originally `IMPLEMENTATION_PLAN.md`) was intentionally **not** imported into KOS knowledge — it is a staged roadmap and should become a hierarchy of KOS tasks rather than a knowledge article.

## Safety Rules

- Stop and ask the human on real clarification, failed checks, suspicious files, secrets, ambiguous scope, or push concerns.
- Do not infer workflow state from repository Markdown once KOS retrieval is verified.
- When durable knowledge in KOS conflicts with observed code or files, verify which is current, update the stale side, and only then act.
