# Owl — Owl-managed Project

This project is managed by Owl. Owl is the authoritative source of workflow state: tasks, workflow definitions, artifact templates, schemas, step status, and runtime config live in the repository under `.owl/`, `tasks/`, and `docs/`, accessed through the `bin/owl` CLI.

The Owl CLI is self-hosted — this repository dogfoods its own tool.

## Runtime

- CLI: `bin/owl` (machine-readable JSON by default).
- Control plane: `.owl/` (config, workflow YAMLs, artifact-type registry, schemas, overlays, runtime state under `.owl/local/`).
- Work zone: `tasks/` (task directories + `tasks/index.yaml`).
- Published knowledge: `docs/` (per workflow `publishes:` rules).
- Static project memory for agents: `docs/agents/` (Constitution, Ruby code architecture, service-objects/OOP, RuboCop, RSpec rules).

## Installed Owl Skills

Materialised by `owl init` into `.claude/skills/owl-*` and `.claude/commands/owl-*`. Refresh by re-running `bin/owl init --force` after changes in `skills/owl-*`.

Primary entrypoints:

- `/owl-orchestrator` — drive the current Owl task through its workflow end-to-end. Default for "what should I work on next?" or "continue".
- `/owl-task-create` — create a new task from a registered workflow.
- `/owl-task-next` — execute the next ready step for the current task.
- `/owl-task-status` — show progress (steps, blockers, children) for the current task.
- `/owl-workflow-show` — render a workflow as ASCII (live by TASK-ID, abstract by `--workflow KEY`).
- `/owl-author` — Q&A author/edit workflow or artifact-type definitions (no manual YAML editing).
- `/owl-init` — re-run the first-run wizard for runtime settings.
- `/owl-cli` — load canonical `bin/owl` usage notes.

Step-level skills (invoked by `/owl-orchestrator`, not normally called by hand):

- `/owl-step-discussion` — run a `session_type: discussion` step in the main session.
- `/owl-step-execution` — run a `session_type: execution` step in an isolated subagent with a structured report.

## Startup Sequence

For any task work, use the smallest CLI path that gives authoritative state before reading repository Markdown:

1. `bin/owl task current --json` — current task pointer (`.owl/local/current.yaml`).
2. `bin/owl task ready-steps <TASK-ID> --json` — next dispatchable steps.
3. `bin/owl step show <TASK-ID> <STEP-ID> --json` — merged bundle: step metadata + context + artifact template + task payload.
4. `bin/owl status <TASK-ID> --json` — progress, blockers, child summary.
5. `bin/owl instructions --json` — current ready step packaged with its skill summary.

Mutating commands: `bin/owl task create | use | abandon | delete --force | child create`, `bin/owl step start | complete | reopen | skip | report`, `bin/owl artifact validate`, `bin/owl publish`, `bin/owl archive`.

## Seeded Workflows

Registered in `.owl/workflows.yaml`:

- `feature` (default) — brief → design → plan → implement → review_code → merge_docs → archive → commit_push.
- `composite_feature` — large feature decomposed into child tasks.
- `hotfix` — urgent fix.
- `refactor` — refactoring with explicit impact analysis.

`hotfix` and `refactor` were scaffolded from `feature`; tailor them via `/owl-author` before serious use.

## Source-Of-Truth Rule

- Task state and workflow status live in `tasks/<TASK-ID>/task.yaml` and are read through `bin/owl`, never inferred from ad-hoc Markdown.
- Project memory for agents lives in `docs/agents/` (read directly):
  - `docs/agents/23_Owl_Project_Constitution.md` — non-negotiable rules for changes in this repo.
  - `docs/agents/27_Owl_Ruby_code_architecture.md` — Backend/Internal/Api layering and FS-access rules.
  - `docs/agents/28_Owl_Ruby_service_objects_and_OOP.md` — service-object style.
  - `docs/agents/29_Owl_Ruby_linting_RuboCop.md` — RuboCop expectations.
  - `docs/agents/30_Owl_Ruby_testing_RSpec_and_public_API_coverage.md` — 100% line coverage for `lib/owl/**/api.rb`.
- Human-readable project background: `AGENTS.md`, `ARCHITECTURE.md`, `REQUIREMENTS.md`, `docs/rfcs/`.
- Historical roadmap: `docs/historical/2026-05-implementation-plan.md` (closed).
- When durable knowledge in `docs/agents/` conflicts with observed code, verify which is current, update the stale side, then act.

## Legacy KOS Snapshot

`.claude/skills/kos-*` and `.claude/commands/kos-*` remain in the repository as a non-active snapshot. They are not the agentic workflow for this project anymore — do not invoke them by default. The KOS application database is untouched and can still be queried manually with `/home/aleksei/plums/kos/bin/kos` if needed.

## Safety Rules

- Stop and ask the human on real clarification, failed checks, suspicious files, secrets, ambiguous scope, or push concerns.
- Do not infer workflow state from repository Markdown when `bin/owl` can answer authoritatively.
- Default to direct push to `main` for Owl-driven deliveries (per existing project convention); confirm before destructive git operations.
