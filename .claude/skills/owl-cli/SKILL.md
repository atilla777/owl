---
name: owl-cli
description: Use the `owl` CLI as the canonical interface to Owl project state — list, inspect, and manipulate tasks, workflows, steps, artifacts.
triggers: ["owl cli", "bin/owl", "owl command", "owl task", "owl step", "owl artifact"]
---

# Skill: owl-cli

## Purpose

`owl-cli` is the shared technical skill for calling `bin/owl` from other Owl-owned skills (`owl-orchestrator`, `owl-step-discussion`, `owl-step-execution`).

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

Do not use this skill to decide what workflow stage runs next, what spec to write, whether an artifact is semantically correct, or whether to commit/push. Those decisions belong to the orchestrator and to `owl-step-discussion` / `owl-step-execution`.

## Source Of Truth

- Treat `bin/owl` JSON responses as authoritative. Do not parse `.owl/` config, `tasks/index.yaml`, or `task.yaml` files directly.
- Treat repository Markdown (`AGENTS.md`, `ARCHITECTURE.md`, `REQUIREMENTS.md`, `docs/historical/2026-05-implementation-plan.md`) as background/historical context only; authoritative workflow state lives in Owl state (`.owl/`, `tasks/`) and is read through `bin/owl`.
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
- `owl task abandon TASK-ID [--reason TEXT]`
- `owl task delete TASK-ID --force`
- `owl task list [--include-abandoned]`
- `owl step start TASK-ID STEP-ID [--variant NAME] [--ignore-modification]`
- `owl step complete TASK-ID STEP-ID [--ignore-modification]`
- `owl step reopen TASK-ID STEP-ID [--cascade]`
- `owl step reset TASK-ID STEP-ID` (return a stuck `running` step to `pending` — claim takeover / `changes_required` re-run)
- `owl step skip TASK-ID STEP-ID --reason "..."`
- `owl step invocation TASK-ID STEP-ID --json`
- `owl step show TASK-ID STEP-ID --json`
- `owl artifact resolve TASK-ID ARTIFACT-TYPE --json`
- `owl artifact validate TASK-ID ARTIFACT-TYPE --json`
- `owl publish TASK-ID --json`
- `owl archive TASK-ID --json`
- `owl instructions TASK-ID [--step-id STEP] --json`
- `owl next [TASK-ID] --json`
- `owl status TASK-ID --json`

Concurrency, plan-approval, and delivery surface (needed by `owl-orchestrator` for the multi-session loop):

- `owl task claim [TASK-ID|--next] [--ttl N] [--label L] [--steal] --json` — atomically take a task lease; returns a `token`.
- `owl task release TASK-ID --token T` — release a held lease immediately.
- `owl task heartbeat TASK-ID --token T [--ttl N]` — extend a held lease before it expires.
- `owl task adopt TASK-ID [--token T] --json` — steal a lease and reset the task's `running` steps to pending.
- `owl task claims --json` / `owl task available --json` / `owl task ready --json` — list live leases / runnable-unclaimed / dependency-ready tasks. **`available` vs `ready` — pick by intent (both exclude claimed + terminal tasks; neither is an alias for the other):**
  - `owl task available` is the **workflow-dispatchability selector**: "which unclaimed tasks have at least one runnable workflow step right now?" It is dependency-blind and parked-status-blind by design — it does not consult `blocked_by` edges or `on_hold`/`blocked` status. Use it to find tasks that have actionable steps.
  - `owl task ready` is the **dependency-DAG view** (added in TASK-0026 for blocks/blocked-by edges): "which unclaimed, non-parked tasks have *all* their `blocked_by` dependencies complete?" It is the cross-task counterpart to `available`: it consults the dependency graph and parked status but ignores whether a workflow step is currently dispatchable. Use it to inspect/debug dependency readiness.
  - For *"what should I actually pick up next?"* prefer `owl next` (or `owl task claim --next`), which uses the **intersection** of both scanners (a candidate must be workflow-dispatchable AND dependency-ready) plus status/priority ordering. Use `available`/`ready` directly when you specifically want one of the two narrower views.
- `owl plan approve TASK-ID [--token T]` / `owl plan status TASK-ID --json` — opt-in plan-approval gate.
- `owl commit-push TASK-ID --message "..."` — transactional stage→complete→commit→push for the `commit_push` step.
- `owl git lock [--name N] [--ttl N] [--steal]` / `owl git unlock --token T [--name N]` — repo-scoped push lock.

The lists above cover the normal workflow + multi-session loop. The long tail (`owl workflow …`, `owl artifact-type …`, `owl spec …`, `owl recall`, `owl task dep|query|label|set-priority|set-status`, `owl verify`, `owl overlay …`, etc.) is reachable via `owl --help`: if an operation is not documented here, fall back to `owl --help`; only stop and report if it is absent there too.

### Response Shape Notes

A few endpoints return shapes that have surprised agents in the past — always iterate the actual JSON structure rather than guessing top-level keys:

- `owl task ready-steps TASK-ID --json` returns `{ready_steps: [...]}`. Each entry has `id`, `skill`, and dependencies metadata.
- `owl step show TASK-ID STEP-ID --json` returns a step bundle whose `step` block carries `variants:` (map) and `default_variant:` when the step declares them, plus the resolved `variant:` for the running task. Use `--variant NAME` on `owl step start` (or `--variant STEP=NAME` on `owl task create`) to choose a non-default variant; the chosen `context_file` and overlay `<step>/<variant>.md` files are then loaded automatically.
- `owl status TASK-ID --json` returns an agent-friendly summary: `steps` (each with a `ready` flag), `progress {done, total, pct}`, `blockers`, and `children` (for composite tasks).
- `owl next [TASK-ID] --json` is the read-only next-action advisor. It returns `{ok, action, task_resolution}`; **all** outcomes exit 0 (a terminal outcome is a valid result, not an error). `action.kind` is one of `dispatch_step` (carries `task_id, step_id, session_type, skill, variant`), `handoff_composite` (carries `task_id, children` aggregate-status), `done` (carries `task_id`), `stop_blocked` (carries `task_id, blocker`), or `no_available_task`. Every `action` object carries the full key set with `null` for inapplicable fields. `task_resolution.source ∈ {explicit, current_pointer, auto_select, none}` with a `reason`, plus `needs_adopt: true` when the chosen task has an expired lease over a stuck `running` step. The command never mutates state (no claim, no step start) — claim/adopt remain explicit follow-up calls.
- `owl task tree --json` and `owl task children PARENT-ID --json` return recursive `{children: [...]}` shapes; walk via recursive descent, not just the top level.
- `owl archive TASK-ID --json` for a composite parent that has unready children returns `composite_with_unready_children` and lists missing children steps — handle this branch before treating the call as a failure.
- `owl artifact validate` returns `{ok: bool, errors: [...]}` — even when the exit code is zero, inspect `ok` before assuming success.

## Canonical Operations

### Project bootstrap

- `owl init` — materialise `.owl/`, seeded workflows (each step bound to the step skill matching its `session_type` — `owl-step-discussion` or `owl-step-execution` — with a per-step `.context.md`), seeded skills (`owl-step-discussion`, `owl-step-execution`, `owl-orchestrator`, `owl-cli`, `owl-task-*` slash commands), and starter artifact templates. Use `--force` to overwrite previously materialised files.
- `owl config validate --json` — validate `.owl/config.yaml` against the JSON Schema; returns `{ok: bool, errors: [...]}`.

### Workflow discovery

- `owl workflow list --json` — list declared workflows with `key`, `kind` (`task` or `composite_task`), and step list.

### Task lifecycle

- `owl task create --workflow KEY --title "..." [--json]` — create a top-level task.
- `owl task child create --parent PARENT-ID --workflow KEY --title "..." [--json]` — create a child task under a composite parent.
- `owl task list [--include-abandoned] --json` — read `tasks/index.yaml`. Excludes tasks with `status: abandoned` by default; `--include-abandoned` opts them back in (archived tasks are physically in `archive/` so they never appear here).
- `owl task inspect TASK-ID --json` — read the full `task.yaml` payload.
- `owl task use TASK-ID` — set `.owl/local/current.yaml` pointer.
- `owl task current --json` — read current task pointer.
- `owl task index rebuild --json` — rebuild `tasks/index.yaml` from on-disk `task.yaml` files.
- `owl task tree [TASK-ID] --json` / `owl task children PARENT-ID --json` / `owl task parent TASK-ID --json` — traverse parent/child relationships.
- `owl task aggregate-status PARENT-ID --json` — aggregate state for a composite parent.
- `owl task abandon TASK-ID [--reason TEXT] --json` — soft-abandon a task. Writes `status: abandoned`, `abandoned_at`, optional `abandon_reason` into `task.yaml`; rebuilds the index. Files stay in place. Idempotent (without `--reason`) on already-abandoned tasks. Returns `task_not_found` for unknown IDs.
- `owl task delete TASK-ID --force --json` — physically remove `tasks/TASK-ID/` and rebuild `tasks/index.yaml`. Without `--force` returns `confirmation_required` and does not touch files. Prints a stderr warning before deletion. Returns `task_not_found` for unknown IDs. Does NOT remove archived tasks under `archive/`.

### Step execution

- `owl task ready-steps TASK-ID --json` — compute the next ready steps from the workflow graph.
- `owl step invocation TASK-ID STEP-ID --json` — full StepInvocation: paths, templates, validation rules, matching skill id.
- `owl step show TASK-ID STEP-ID --json` — merged step + context + artifact_template + task bundle (preferred for `owl-step-discussion` / `owl-step-execution`).
- `owl step start TASK-ID STEP-ID [--variant NAME] [--ignore-modification]` — mark a ready step as running; `--variant` is required when the step declares `variants:` and no choice was made at task-create time (or to override one). `--ignore-modification` suppresses the `artifact_modified_after_complete` warning printed to stderr when the artifact file was changed outside the sequencer since the last `step complete`.
- `owl step complete TASK-ID STEP-ID [--ignore-modification]` — mark a running step as done; re-runs artifact validation as a safety net. On success, records `content_sha` (sha256 hex of the artifact file) per artifact in `task.yaml`. `--ignore-modification` suppresses drift warning.
- `owl step reopen TASK-ID STEP-ID [--cascade]` — move a done step back to `pending`. With `--cascade`, also pendifies every step that transitively requires the reopened one. Fails with `step_not_completed` if the step is not done, or `artifact_missing` if the artifact file has been deleted.
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
- the requested operation is documented neither here nor in `owl --help` — do not invent a flag (a command reachable via `owl --help` is **not** a stop; use it)

## Verification

Verify this skill by:

- checking that every documented command above exists in the current `bin/owl --help` output
- confirming JSON response shapes against integration specs under `spec/cli/...`
- running `bundle exec rspec spec/owl/skills/seeded_sources_spec.rb spec/owl/cli/init_skills_spec.rb` after changes to `lib/owl/skills/internal/seeded_sources.rb`
- confirming `owl init` in a clean directory materialises `.claude/skills/owl-cli/SKILL.md` and `.claude/commands/owl-cli.md`
