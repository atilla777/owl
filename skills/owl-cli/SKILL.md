---
name: owl-cli
description: Use the `owl` CLI as the canonical interface to Owl project state — list, inspect, and manipulate tasks, workflows, steps, artifacts.
triggers: ["owl cli", "bin/owl", "owl command", "owl task", "owl step", "owl artifact"]
---

# Skill: owl-cli

## Purpose

`owl-cli` is the shared technical skill for calling `bin/owl` from other Owl-owned skills (`owl-orchestrator`, `owl-step-run`).

Use it to keep skills focused on their scoped work instead of rebuilding CLI argument shapes, JSON response keys, error semantics, and the no-direct-filesystem-access invariant.

The `owl` CLI is the **only** sanctioned interface to `.owl/` and `tasks/` state. Skills must not read those directories with `Read`/`Bash cat`/`grep`/`find` — go through `owl ...` instead.

## When To Use

Use this skill when another skill needs to:

- resolve or initialise an Owl project layout
- list, create, inspect, or switch tasks
- inspect or rebuild the task index, walk parent/child trees, or aggregate composite status
- compute ready steps, package step invocations or step+context+artifact bundles
- start, complete, or skip a step
- resolve artifact paths and validate artifact bodies
- publish task artifacts into the docs storage role
- archive a completed task subtree
- get the next-step instructions packet for an agent
- report workflow status for a task

Do not use this skill to decide what workflow stage runs next, what spec to write, whether an artifact is semantically correct, or whether to commit/push. Those decisions belong to the orchestrator and to `owl-step-run`.

## Source Of Truth

- Treat `bin/owl` JSON responses as authoritative. Do not parse `.owl/` config, `tasks/index.yaml`, or `task.yaml` files directly.
- Treat repository Markdown (`AGENTS.md`, `ARCHITECTURE.md`, `REQUIREMENTS.md`, `IMPLEMENTATION_PLAN.md`) as historical fallback after KOS migration; current workflow state lives in KOS application state.
- When `bin/owl` returns a structured error, surface its message to the caller rather than guessing recovery — the CLI is the contract.
- Pass `--json` to every read command that supports it; agent-facing commands return stable JSON shapes designed for parsing.

## Inputs

- repository root with `.owl/config.yaml` (created by `owl init`)
- `TASK-ID` for task-scoped commands; resolve the current one via `owl task current --json` when the caller did not pass one explicitly
- step id for step-scoped commands; obtain it via `owl task ready-steps TASK-ID --json` or `owl status TASK-ID --json`
- artifact type key (`spec`, `tasks`, `verification`, etc.) for artifact-scoped commands

## Outputs

- parsed JSON from `bin/owl <subcommand> --json`
- structured error message (non-zero exit) when the CLI rejects the operation
- no hidden persisted state outside `.owl/`, `tasks/`, `docs/`, and `tasks/archive/`

## CLI Usage

Use `bin/owl` (or `owl` when installed on PATH) as the standard wrapper for project state operations. The agent-facing commands below are the documented contract. Use `owl --help` only when troubleshooting a command that is missing from this skill.

Representative commands:

- `owl init [--root PATH] [--force]`
- `owl workflow list --json`
- `owl config validate --json`
- `owl task create --workflow KEY --title "..." [--parent PARENT-ID] [--variant STEP=NAME] [--json]`
- `owl task list --json`
- `owl task inspect TASK-ID --json`
- `owl task use TASK-ID`
- `owl task current --json`
- `owl task ready-steps TASK-ID --json`
- `owl task index rebuild --json`
- `owl task tree [TASK-ID] --json`
- `owl task children PARENT-ID --json`
- `owl task parent TASK-ID --json`
- `owl task aggregate-status PARENT-ID --json`
- `owl task child create --parent PARENT-ID --workflow KEY --title "..." [--json]`
- `owl step start TASK-ID STEP-ID [--variant NAME]`
- `owl step complete TASK-ID STEP-ID`
- `owl step skip TASK-ID STEP-ID --reason "..."`
- `owl step invocation TASK-ID STEP-ID --json`
- `owl step show TASK-ID STEP-ID --json`
- `owl artifact resolve TASK-ID ARTIFACT-TYPE --json`
- `owl artifact validate TASK-ID ARTIFACT-TYPE --json`
- `owl publish TASK-ID --json`
- `owl archive TASK-ID --json`
- `owl instructions TASK-ID [--step-id STEP] --json`
- `owl status TASK-ID --json`

The list above is intentionally explicit so agents do not need CLI discovery for normal workflows. If a needed operation is not listed here, stop and report the missing CLI contract instead of guessing a flag.

### Response Shape Notes

A few endpoints return shapes that have surprised agents in the past — always iterate the actual JSON structure rather than guessing top-level keys:

- `owl task ready-steps TASK-ID --json` returns `{ready_steps: [...]}`. Each entry has `id`, `skill`, and dependencies metadata.
- `owl step show TASK-ID STEP-ID --json` returns a step bundle whose `step` block carries `variants:` (map) and `default_variant:` when the step declares them, plus the resolved `variant:` for the running task. Use `--variant NAME` on `owl step start` (or `--variant STEP=NAME` on `owl task create`) to choose a non-default variant; the chosen `context_file` and overlay `<step>/<variant>.md` files are then loaded automatically.
- `owl status TASK-ID --json` returns an agent-friendly summary: `steps` (each with a `ready` flag), `progress {done, total, pct}`, `blockers`, and `children` (for composite tasks).
- `owl task tree --json` and `owl task children PARENT-ID --json` return recursive `{children: [...]}` shapes; walk via recursive descent, not just the top level.
- `owl archive TASK-ID --json` for a composite parent that has unready children returns `composite_with_unready_children` and lists missing children steps — handle this branch before treating the call as a failure.
- `owl artifact validate` returns `{ok: bool, errors: [...]}` — even when the exit code is zero, inspect `ok` before assuming success.

## Canonical Operations

### Project bootstrap

- `owl init` — materialise `.owl/`, seeded workflows (each step bound to `owl-step-run` with a per-step `.context.md`), seeded skills (`owl-step-run`, `owl-orchestrator`, `owl-cli`, `owl-task-*` slash commands), and starter artifact templates. Use `--force` to overwrite previously materialised files.
- `owl config validate --json` — validate `.owl/config.yaml` against the JSON Schema; returns `{ok: bool, errors: [...]}`.

### Workflow discovery

- `owl workflow list --json` — list declared workflows with `key`, `kind` (`task` or `composite_task`), and step list.

### Task lifecycle

- `owl task create --workflow KEY --title "..." [--json]` — create a top-level task.
- `owl task child create --parent PARENT-ID --workflow KEY --title "..." [--json]` — create a child task under a composite parent.
- `owl task list --json` — read `tasks/index.yaml`.
- `owl task inspect TASK-ID --json` — read the full `task.yaml` payload.
- `owl task use TASK-ID` — set `.owl/local/current.yaml` pointer.
- `owl task current --json` — read current task pointer.
- `owl task index rebuild --json` — rebuild `tasks/index.yaml` from on-disk `task.yaml` files.
- `owl task tree [TASK-ID] --json` / `owl task children PARENT-ID --json` / `owl task parent TASK-ID --json` — traverse parent/child relationships.
- `owl task aggregate-status PARENT-ID --json` — aggregate state for a composite parent.

### Step execution

- `owl task ready-steps TASK-ID --json` — compute the next ready steps from the workflow graph.
- `owl step invocation TASK-ID STEP-ID --json` — full StepInvocation: paths, templates, validation rules, matching skill id.
- `owl step show TASK-ID STEP-ID --json` — merged step + context + artifact_template + task bundle (preferred for `owl-step-run`).
- `owl step start TASK-ID STEP-ID [--variant NAME]` — mark a ready step as running; `--variant` is required when the step declares `variants:` and no choice was made at task-create time (or to override one).
- `owl step complete TASK-ID STEP-ID` — mark a running step as done; re-runs artifact validation as a safety net.
- `owl step skip TASK-ID STEP-ID --reason "..."` — mark an optional step as skipped.
- `owl instructions TASK-ID [--step-id STEP] --json` — package the next ready step with its `SKILL.md` summary.

### Artifacts

- `owl artifact resolve TASK-ID ARTIFACT-TYPE --json` — task-scoped artifact path, template URI, and validation rules.
- `owl artifact validate TASK-ID ARTIFACT-TYPE --json` — validate existence, sections, regex patterns, frontmatter against the template.

### Publishing and archiving

- `owl publish TASK-ID --json` — copy approved artifacts to `docs/<...>` per the workflow's `publishes` rules; writes `.backup-<ts>` siblings when overwriting.
- `owl archive TASK-ID --json` — move `tasks/TASK-ID/` into `tasks/archive/<date>-<TASK-ID>-<slug>/`, update `tasks/index.yaml`, set the task `status: archived`. For composite parents, archives the full subtree atomically; if any child is not ready it returns `composite_with_unready_children`.

### Status reporting

- `owl status TASK-ID --json` — agent-friendly progress summary; preferred over raw `task inspect` when the caller wants `ready`/`done` per step plus aggregate `progress` and `blockers`.

## Stop Conditions

Stop and return control to the calling skill when:

- `.owl/config.yaml` is missing (`owl init` has not been run)
- the CLI rejects the operation with a structured error that requires human judgment (e.g. invalid workflow key, schema mismatch)
- a composite operation returns `composite_with_unready_children` and the caller did not ask for partial handling
- an artifact validation fails (`ok: false`) and the calling skill cannot fix the body without scope or product input
- the requested operation is not represented in this skill or in `owl --help` — do not invent a flag

## Verification

Verify this skill by:

- checking that every documented command above exists in the current `bin/owl --help` output
- confirming JSON response shapes against integration specs under `spec/cli/...`
- running `bundle exec rspec spec/owl/skills/seeded_sources_spec.rb spec/owl/cli/init_skills_spec.rb` after changes to `lib/owl/skills/internal/seeded_sources.rb`
- confirming `owl init` in a clean directory materialises `.claude/skills/owl-cli/SKILL.md` and `.claude/commands/owl-cli.md`
