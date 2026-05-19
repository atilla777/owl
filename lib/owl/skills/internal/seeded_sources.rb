# frozen_string_literal: true

module Owl
  module Skills
    module Internal
      module SeededSources # rubocop:disable Metrics/ModuleLength
        module_function

        ORCHESTRATOR_BODY = <<~MD
          ---
          name: owl-orchestrator
          description: Drive an Owl task through its workflow end-to-end. Read state through the `owl` CLI, delegate each ready step to the universal `owl-step-run` skill, stop on real human decisions.
          triggers: ["owl orchestrator", "continue owl task", "drive owl workflow", "next owl step"]
          ---

          ## Purpose

          Drive an Owl task from its current ready step to the workflow's terminal step using the `owl` CLI as the sole source of truth. Every seeded step binds the universal `owl-step-run` skill; the orchestrator's job is to pick the next ready step and trust that binding. The orchestrator stays skill-binding-agnostic so a custom workflow that names a different skill still resolves through `owl instructions`.

          ## When To Use

          - The user has a current Owl task and asks to continue, do the next step, or names a specific `TASK-ID`.
          - A new task was just created and is ready for its first step.
          - A previous orchestrator run was interrupted and needs to resume from the current ready step.

          Do not use this skill to invent workflow stages, edit `.owl/` config, or run product/scope decisions on behalf of the human.

          ## Inputs

          - Current `TASK-ID` from `owl task current --json` or an explicit `TASK-XXXX` argument.
          - Optional `STEP-ID` when the human names one explicitly; otherwise pick the first entry from `owl task ready-steps TASK-ID --json`.

          ## Outputs

          - Each step's artifact (when the step declares one) written through the executor skill at the path returned by `owl artifact resolve` and validated `ok: true` by `owl artifact validate`.
          - Step status advanced through `owl step start` / `owl step complete` / `owl step skip` — owl re-runs the validate gate at `complete` time.
          - Workflow-terminal effects when the workflow declares them (typically `owl publish` and `owl archive`).
          - A short human-facing summary at end of run, or a stop report when human input is required.

          ## Workflow

          1. Resolve the active task: `owl task current --json`. If the user named a different task, switch with `owl task use TASK-ID`.
          2. Inspect progress: `owl status TASK-ID --json` returns the agent-friendly summary (steps with `ready` flag, `progress {done, total, pct}`, blockers, `children` for composite tasks). Fall back to `owl task inspect TASK-ID --json` only when the raw `task.yaml` payload is needed.
          3. Pick the next ready step: `owl task ready-steps TASK-ID --json`. Take the first entry unless the user named one. Do not invent a step id that is not in the ready set.
          4. Resolve the bound skill: `owl instructions TASK-ID --step-id STEP --json` returns the step invocation packaged with the matching `SKILL.md` path, slash-command path, and a one-paragraph summary. For seeded workflows the binding is always `owl-step-run`; a custom workflow can name its own skill and the orchestrator delegates verbatim. Use `owl step invocation TASK-ID STEP --json` when only the raw invocation block is needed.
          5. Delegate execution to the bound skill. It is responsible for `owl step start`, generating the artifact (when one is declared), and producing valid output. Pass the `TASK-ID` and `STEP-ID` to the delegated skill; do not paste step-specific instructions inline.
          6. After delegation returns:
             - Re-validate the artifact: `owl artifact validate TASK-ID ARTIFACT-KEY --json` returns `{ok, errors}`. Inspect `ok` before assuming success.
             - Mark the step complete: `owl step complete TASK-ID STEP-ID`. Owl re-runs the validate gate at complete time as a safety net.
          7. Loop from step 2 until `owl task ready-steps` returns empty AND the workflow's terminal step (typically `archive`) is done. Stop and report when no more progress is possible.

          ## Stop Conditions

          Stop and return control to the human with a concrete decision request when:

          - artifact validation fails twice in a row on the same step and the second pass would require a product, scope, or data decision;
          - `owl task ready-steps` returns empty but the workflow's terminal step is not done (the workflow graph has an unsatisfied dependency the human must unblock);
          - `git status` shows suspicious or unrelated files in the working tree, making the step's scope ambiguous;
          - the delegated step skill returns its own stop condition (e.g., `owl-step-run` could not infer the step's purpose from the supplied `context`);
          - a `composite_feature` parent reaches `aggregate_verify` while child tasks are still in progress (`owl task aggregate-status PARENT-ID --json` reports unready children);
          - `owl publish` or `owl archive` would overwrite content that does not look like a `.backup-<timestamp>` candidate or that lives outside the current task tree;
          - the `owl` CLI returns a structured error (`task_workflow_missing`, `unknown_step_id`, `step_not_ready`, `composite_with_unready_children`, etc.) that the orchestrator cannot resolve through one obvious retry.

          When stopping, report the active `TASK-ID`, the step that failed or blocked progress, the `owl ...` command output, and one explicit question for the human.

          ## Notes

          - `owl step skip TASK-ID STEP --reason "..."` is allowed only for steps the workflow YAML marks optional. Do not skip required steps to make progress — fix the underlying issue or stop.
          - For `composite_feature` tasks: `decompose` spawns child tasks; `coordinate` tracks them; `aggregate_verify` rolls up child verification reports. Use `owl task tree TASK-ID --json` / `owl task children PARENT-ID --json` / `owl task aggregate-status PARENT-ID --json` to inspect the subtree. `owl archive PARENT-ID --json` archives the full subtree atomically — if any child is unready, it returns `composite_with_unready_children` rather than partial archive.
          - The full `bin/owl` command surface, JSON response shapes, and error semantics are documented in the `owl-cli` skill — consult that reference rather than parsing `owl --help`.
          - In the universal-step model, every seeded step's `skill:` binding resolves to `owl-step-run`; that skill reads per-step `context` from `owl step show` and produces the declared artifact without hardcoded step-type knowledge. The orchestrator's job is to pick the step and trust the binding.
          - Never read `.owl/`, `tasks/`, or `docs/` files directly. Always go through `owl ...` CLI. This is an architectural invariant of Owl.
        MD

        TASK_COMMANDS = {
          'owl-task-create' => <<~MD,
            ---
            description: Create a new Owl task from a registered workflow.
            ---
            Use `owl task create --workflow <key> --title "..." --json` to create a new task. Pick a workflow from `owl workflow list --json` (typically `feature` for a new feature, `hotfix` for an incident, `research` for an investigation, `composite_feature` when the work will spawn children).

            After creation, set the task current with `owl task use TASK-ID` and run the orchestrator with `/owl-orchestrator` to start the first step.

            Use the command arguments as title / workflow hints: $ARGUMENTS
          MD
          'owl-task-status' => <<~MD,
            ---
            description: Show progress for the current Owl task.
            ---
            Resolve the current task and report progress.

            1. `owl task current --json` to get TASK-ID (or use $ARGUMENTS if a TASK-ID is supplied).
            2. `owl status TASK-ID --json` for the agent-friendly summary (steps with `ready` flag, progress done/total/pct, blockers, `children` for composite tasks).

            Fall back to `owl task inspect TASK-ID --json` + `owl task ready-steps TASK-ID --json` only when you need the raw underlying payload.

            $ARGUMENTS
          MD
          'owl-task-next' => <<~MD
            ---
            description: Do the next ready step for the current Owl task.
            ---
            Pick the next ready step and run it via `/owl-orchestrator`.

            1. `owl task current --json` to get the current TASK-ID (use $ARGUMENTS to override).
            2. `owl task ready-steps TASK-ID --json` — take the first ready step.
            3. Dispatch to `/owl-orchestrator` with that TASK-ID + step hint; the orchestrator delegates to `owl-step-run`.

            $ARGUMENTS
          MD
        }.freeze

        ORCHESTRATOR_SLASH = <<~MD
          ---
          description: Drive an Owl task through its workflow end-to-end.
          ---
          Load skill `owl-orchestrator`.

          Use the command arguments as workflow intent (TASK-ID, step hint, or free-form): $ARGUMENTS

          Rules:
          - if there are no arguments, continue or claim the current Owl task via `owl task current --json`.
          - if the arguments name a TASK-ID, set it current with `owl task use TASK-ID` first.
          - never read `.owl/` or `tasks/` directly — go through `owl ...` CLI.
        MD

        OWL_CLI_BODY = <<~MD
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
          - list, create, inspect, switch, or split tasks
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
          - `owl task create --workflow KEY --title "..." [--parent PARENT-ID] [--json]`
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
          - `owl task split TASK-ID --workflow KEY [--json]`
          - `owl step start TASK-ID STEP-ID`
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
          - `owl task split TASK-ID --workflow KEY [--json]` — convert a task into a `composite_task`.
          - `owl task index rebuild --json` — rebuild `tasks/index.yaml` from on-disk `task.yaml` files.
          - `owl task tree [TASK-ID] --json` / `owl task children PARENT-ID --json` / `owl task parent TASK-ID --json` — traverse parent/child relationships.
          - `owl task aggregate-status PARENT-ID --json` — aggregate state for a composite parent.

          ### Step execution

          - `owl task ready-steps TASK-ID --json` — compute the next ready steps from the workflow graph.
          - `owl step invocation TASK-ID STEP-ID --json` — full StepInvocation: paths, templates, validation rules, matching skill id.
          - `owl step show TASK-ID STEP-ID --json` — merged step + context + artifact_template + task bundle (preferred for `owl-step-run`).
          - `owl step start TASK-ID STEP-ID` — mark a ready step as running.
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
        MD

        OWL_CLI_SLASH = <<~MD
          ---
          description: Load the owl-cli skill for canonical bin/owl usage.
          ---
          Load skill `owl-cli`.

          Use the command arguments as command intent (subcommand hint, TASK-ID, free-form): $ARGUMENTS

          Rules:
          - never read `.owl/` or `tasks/` directly — go through `owl ...` CLI.
          - prefer `--json` for read operations; iterate the documented response shapes.
        MD

        OWL_STEP_RUN_BODY = <<~MD
          ---
          name: owl-step-run
          description: Execute any Owl workflow step generically by reading its per-step context bundle through `owl step show` and producing the declared artifact — no hardcoded step type knowledge.
          triggers: ["owl step run", "run owl step", "execute owl step", "owl step generic"]
          ---

          ## Purpose

          `owl-step-run` is the universal step execution skill. One skill executes any step on any seeded or custom workflow because the step-specific behaviour lives in the workflow's per-step `context` (inline `step.context` string or referenced `step.context_file`), not in the skill body.

          The skill reads the merged bundle from `owl step show`, interprets the step's purpose and acceptance criteria from the supplied `context`, generates the artifact body declared by `artifact_template`, writes it at the path returned by `owl artifact resolve`, validates it through `owl artifact validate`, and completes the step via `owl step complete`.

          ## When To Use

          - The orchestrator (or a human) names a ready step on an Owl task and asks you to execute it.
          - The step in the workflow YAML declares either an inline `context` block or a `context_file` reference — those carry the actual instructions for this particular step.
          - You are working through a seeded or custom workflow and prefer one universal executor over per-step specialised skills.

          Do not use this skill to plan task scope, decide step ordering, or interpret workflow definitions outside the supplied bundle. Workflow choice and step ordering belong to the Owl CLI graph (`owl task ready-steps`); product or scope decisions belong to the human.

          ## Inputs

          - `TASK-ID` (from `owl task current --json` or an explicit argument).
          - `STEP-ID` chosen from `owl task ready-steps TASK-ID --json` (or the value `owl-orchestrator` handed you).
          - The bundle returned by `owl step show TASK-ID STEP-ID --json`:
            - `step` — the step payload (id, status, declared inputs, declared `creates` artifact key, etc.) without the `context` field.
            - `context` — the per-step instruction text (string or null when the step has no per-step context).
            - `artifact_template` — `{required_sections, frontmatter_schema}` for the step's declared artifact (null when the step produces no artifact).
            - `task` — `{id, title, spec_body}` so you can read the parent task's spec for cross-step continuity.

          ## Outputs

          - When the step declares an artifact: a file written at the path returned by `owl artifact resolve`, containing the required sections and frontmatter from `artifact_template`, validated `ok: true` by `owl artifact validate`.
          - When the step has no artifact (for example, a pure code-change or CLI step): the side effect described in `context` (repository changes, a `owl publish` invocation, etc.). No KOS-style artifact is required.
          - Step status advanced through `owl step complete TASK-ID STEP-ID`.

          ## Workflow

          1. Resolve the task: `owl task current --json` (or use the supplied `TASK-ID`).
          2. Choose a ready step: `owl task ready-steps TASK-ID --json` and take the requested or first ready entry; do not invent steps that are not in the ready set.
          3. Mark the step started: `owl step start TASK-ID STEP-ID`.
          4. Load the bundle: `owl step show TASK-ID STEP-ID --json`. Read `step`, `context`, `artifact_template`, and `task`.
          5. Interpret `context` as the authoritative description of this step's purpose, acceptance criteria, and any step-specific hints. Read `task.spec_body` for cross-step continuity.
          6. If `artifact_template` is present:
             - Resolve the destination path: `owl artifact resolve TASK-ID ARTIFACT-KEY --json` (the `ARTIFACT-KEY` is in `step.creates`).
             - Generate Markdown body that covers every entry of `artifact_template.required_sections` and a YAML frontmatter matching `artifact_template.frontmatter_schema`.
             - Write the file at the resolved path. Do not invent paths; do not write outside `tasks/<TASK-ID>/`.
             - Validate: `owl artifact validate TASK-ID ARTIFACT-KEY --json`. If `ok` is false, read `errors`, fix the body, re-validate. Do not proceed until `ok: true`.
          7. If the step has no artifact, execute the side effect described in `context` (for example, run the documented CLI subcommand, or perform the documented code change scoped to the task).
          8. Complete the step: `owl step complete TASK-ID STEP-ID`. Owl re-runs the artifact validate gate here as a safety net.
          9. Return control to the orchestrator (or to the human if invoked directly). Do not chain to the next step unless explicitly asked.

          ## Stop Conditions

          Stop and report when:

          - `owl task ready-steps` does not list the requested step (likely a dependency is incomplete).
          - `owl step show` returns `unknown_step_id`, `task_workflow_missing`, or any other structured error.
          - `context` is empty or absent and the step's purpose cannot be derived from `step.creates` + `task.spec_body` alone — the workflow YAML is incomplete and the human needs to fill it.
          - `owl artifact validate` reports errors that require product, scope, or data decisions the human must make.
          - the requested artifact path is unsafe, points outside the task tree, or already exists with unrelated content.
          - the step requires repository changes outside the current task's scope.

          ## Verification

          - Round-trip: after `owl step complete`, `owl status TASK-ID --json` shows the step `done` and the next step's `ready: true` flag flips correctly.
          - Artifact path returned by `owl artifact resolve` exists on disk after the run.
          - `owl artifact validate TASK-ID ARTIFACT-KEY --json` returns `ok: true` both before and after `owl step complete`.

          ## Notes

          - The full `bin/owl` command surface, JSON response shapes, and error semantics are documented in the `owl-cli` skill. This skill assumes that reference is available; do not duplicate command tables here.
          - This skill is intentionally generic: it does not switch behaviour on `STEP-ID` value. If you find yourself special-casing a particular step id, add the rule to that step's `context` in the workflow YAML instead of branching here.
          - Never read `.owl/`, `tasks/`, or `docs/` files directly to discover state — always go through `owl ...` CLI commands.
        MD

        OWL_STEP_RUN_SLASH = <<~MD
          ---
          description: Execute any ready Owl workflow step through the universal owl-step-run skill.
          ---
          Load skill `owl-step-run`.

          Use the command arguments as `TASK-ID` + optional `STEP-ID` (or free-form intent): $ARGUMENTS

          Rules:
          - if no TASK-ID supplied, resolve it via `owl task current --json`.
          - never invent a step id; pick from `owl task ready-steps TASK-ID --json`.
          - never read `.owl/` or `tasks/` directly — go through `owl ...` CLI.
        MD

        OWL_INIT_BODY = <<~MD
          ---
          name: owl-init
          description: First-run wizard that interviews the user for Owl runtime settings (language, storage, optional workflows) and writes them to `.owl/config.yaml` via `owl config set`. One-shot bootstrap — not for mid-project re-config.
          triggers: ["owl init", "owl-init", "initialize owl", "owl wizard", "owl first run", "configure owl"]
          ---

          # Skill: owl-init

          ## Purpose

          `owl-init` is the agent-driven first-run wizard for a fresh Owl project. It asks the user a small fixed set of questions through the harness Q&A surface (`AskUserQuestion`), records each answer through `owl config set settings.* VALUE`, and runs a final `owl config validate --json` to confirm the new config is healthy.

          The wizard is the **only** sanctioned UX for creating the initial `settings:` block of `.owl/config.yaml`. CLI surface for runtime modification is `bin/owl config get|set|show` (documented in `owl-cli`); this skill is the **one-shot bootstrap** that fills the block in the first place.

          ## When To Use

          - The user is on a brand-new project that has just run `owl init` (or is about to) and needs to choose runtime settings (language, storage backend, role paths, optional workflows).
          - The user asks to "initialize owl", "configure owl", "run the owl wizard", or supplies a fresh repository with empty `.owl/config.yaml` settings.

          Do not use this skill to:

          - **mid-project re-config**: the wizard refuses if `settings.language.communication` is already set unless the user explicitly confirms re-configuration. For ongoing edits, use `bin/owl config set settings.* VALUE` directly or delegate to `owl-author` for workflow/artifact edits.
          - run product/scope decisions on behalf of the user.
          - edit anything outside `settings.*` — top-level `project:`, `workflow:`, and legacy `storage:` blocks are not part of this skill's surface.

          ## Inputs

          - Repository root with a `.owl/config.yaml` produced by `owl init` (or the wizard runs `owl init` first when the file is missing).
          - User answers through harness Q&A (`AskUserQuestion`) — six questions total, several with sensible defaults so the user can accept the whole flow with just confirmations.

          ## Outputs

          - `.owl/config.yaml` `settings:` block populated with the user's choices:
            - `settings.language.communication` (required)
            - `settings.language.artifacts` (inherits from communication or user override)
            - `settings.language.docs` (inherits from communication or user override)
            - `settings.storage.backend` (`filesystem` in v1)
            - `settings.storage.roles.tasks|docs|archive` (defaults shown; per-role override on opt-in)
            - `settings.workflows.enabled` (optional list)
          - A short user-facing summary report in `settings.language.communication` describing what was recorded.

          ## Workflow

          1. **Pre-flight**: confirm `bin/owl` is reachable and a project root exists.
             - Run `owl config show --root . --json`. If it returns `config_missing`, run `owl init --root .` first.
             - Run `owl config get settings.language.communication --root . --json`. If the call succeeds (key already set), ask the user: "Settings are already configured (communication=<value>). Re-run wizard?" If the user declines, exit no-op with a summary.

          2. **Q1 — communication language (required, no default)**:
             - English-language prompt: "Which language should agents use for user-facing communication? (e.g. en, ru, es)"
             - Persist: `owl config set settings.language.communication <answer>`.

          3. **Q2 — artifacts language (default = communication)**:
             - Localized prompt in `<communication>` language: "Same language for artifacts as for communication? [Y/n]"
             - If Y: `owl config set settings.language.artifacts <communication_value>`.
             - If n: ask for the value, then `owl config set settings.language.artifacts <answer>`.

          4. **Q3 — docs language (default = communication)**: same shape as Q2.
             - If Y: `owl config set settings.language.docs <communication_value>`.
             - If n: ask for the value, then `owl config set settings.language.docs <answer>`.

          5. **Q4 — storage backend**: `filesystem` is the only supported v1 backend; record it without prompting: `owl config set settings.storage.backend filesystem`.

          6. **Q5 — storage role paths**:
             - Show the defaults table to the user (`tasks → ./tasks`, `docs → ./docs`, `archive → ./tasks/archive`).
             - Ask: "Accept default storage role paths? [Y/n]"
             - On Y: no per-role prompts (defaults are already in the config from `owl init`).
             - On n: ask per role and run `owl config set settings.storage.roles.<role> <answer>` for each override.

          7. **Q6 — workflows enable list (optional)**:
             - Show a multi-select of `owl workflow list --json` results.
             - Ask: "Which workflows do you want enabled? (leave empty to allow all)"
             - On selection: `owl config set settings.workflows.enabled '["..."]'` (JSON array literal).
             - Empty selection: `owl config set settings.workflows.enabled '[]'` (explicit empty list).

          8. **Final validation**:
             - Run `owl config validate --root . --json`.
             - On `ok: true`: print a localized summary of the recorded settings.
             - On `ok: false`: report the validation errors and stop; the user must fix manually via `owl config set` or restart the wizard.

          ## Language Clause (constitution 5.16, 5.17)

          - SKILL.md content is English (canonical contract; constitution 5.16).
          - **Before Q1 is answered**, the wizard speaks **English** to the user: the communication language is not yet known.
          - **After Q1**: the wizard switches to `settings.language.communication` for all subsequent prompts, status messages, and the final summary.
          - Downstream Owl skills (`owl-orchestrator`, `owl-step-run`) read `settings.language.communication` through `owl step show --json` or `owl config show --json` and respect it for their own user-facing reports.
          - `required_sections` literal headings in artifact templates remain English regardless of `settings.language.artifacts` (template identity is part of schema validation).

          ## Stop Conditions

          Stop and return control to the user with a concrete decision request when:

          - `bin/owl` is not on PATH, or `owl init` fails (cannot create `.owl/`).
          - `owl config show` reports `config_missing` and `owl init` cannot be run safely (existing files in the way).
          - the user declines re-configuration on an already-initialized project — exit no-op with a summary; do not silently overwrite.
          - `owl config set` returns a structured error (`unsupported_config_path`, `config_validation_failed`, `invalid_config_value`) — surface the message and ask the user how to proceed.
          - `owl config validate` after wizard completion reports `valid: false` — show the errors and stop.
          - the user provides ambiguous input that cannot be normalized to a stable string or JSON literal (for the workflows list).

          ## Verification

          - After a complete wizard run on a freshly initialized project, `owl config validate --root . --json` returns `{ok: true, valid: true, errors: []}`.
          - `owl config get settings.language.communication --root . --json` returns the user-chosen value.
          - `owl config show --root . --json` reflects the full set of recorded `settings.*` keys.

          ## Notes

          - The wizard never reads or writes `.owl/config.yaml` directly. All persistence flows through `owl config set` (constitution 5.15: "Owl CLI as the only state interface").
          - JSON-array literal syntax for `owl config set`: pass single-quoted JSON, e.g. `owl config set settings.workflows.enabled '["feature","bugfix"]'`. The empty list is `'[]'`.
          - The wizard is intentionally minimal. New `settings.*` fields are added by extending this skill's Q&A and the validator schema, not by inventing a new CLI subcommand.
          - This skill is one-shot. For changing a single setting later, use `bin/owl config set settings.<path> <value>` (see `owl-cli`).
        MD

        OWL_INIT_SLASH = <<~MD
          ---
          description: Run the Owl first-run wizard to configure settings (language, storage, optional workflows).
          ---
          Load skill `owl-init`.

          Use the command arguments as wizard intent (free-form): $ARGUMENTS

          Rules:
          - never edit `.owl/config.yaml` directly — go through `owl config set settings.*` for every recorded answer.
          - speak English until `settings.language.communication` is recorded; switch to that language afterwards.
          - this skill is one-shot bootstrap; for mid-project edits use `bin/owl config set` directly.
        MD

        OWL_AUTHOR_BODY = <<~MD
          ---
          name: owl-author
          description: Universal Q&A authoring skill for Owl workflow definitions and artifact-type definitions. Creates new ones, edits existing ones, drives every change through `bin/owl workflow|artifact-type` CLI. Respects `settings.language.*`.
          triggers: ["owl author", "owl-author", "author workflow", "author artifact", "create workflow", "create artifact-type", "edit workflow", "edit artifact-type", "new workflow", "new artifact-type"]
          ---

          # Skill: owl-author

          ## Purpose

          `owl-author` is the agent-driven authoring surface for Owl workflow definitions (`.owl/workflows/<id>/workflow.yaml`) and artifact-type definitions (`.owl/artifacts/<id>/artifact.yaml`). It interviews the user through the harness Q&A surface (`AskUserQuestion`), drafts the resulting YAML body in memory, and persists every change through the `bin/owl workflow ...` / `bin/owl artifact-type ...` CLI. The skill never reads or writes those files directly — constitution 5.13 (skill layering) and 5.15 (Owl CLI as the only state interface).

          The skill has three modes:

          - **Mode A — Create workflow**: scaffold a new workflow definition and walk the user through filling in steps/artifacts.
          - **Mode B — Create artifact-type**: scaffold a new artifact-type definition and walk the user through required_sections / front_matter / template body.
          - **Mode C — Edit existing**: load a current definition via `owl workflow show` or `owl artifact-type show`, present its structure, gather a structured delta, and rewrite via `--force`.

          ## When To Use

          - The user asks to "create a new workflow", "add a workflow for X", "design an artifact type for Y", "edit the feature workflow", "tweak the brief artifact", etc.
          - The user supplies a rough sketch of a workflow (steps, artifacts) and wants the skill to formalize it into a valid YAML.

          Do not use this skill for:

          - registering a workflow / artifact-type in `.owl/workflows.yaml` / `.owl/artifacts.yaml` — the `new` CLI deliberately writes only the source file; registry inclusion is an explicit follow-up step (manual edit) so ad-hoc experiments do not pollute the registry.
          - editing task-scoped artifacts (use `owl-step-run` instead — those are per-task artifact files in `tasks/`).
          - mid-stream renames of an existing definition that already has child tasks bound to it (out of scope for v1; flag as a separate task).
          - configuring runtime settings (`settings.*`) — that's `owl-init` for bootstrap and `owl config set` for ongoing edits.

          ## Inputs

          - Optional `mode: A|B|C` from the slash-command argument.
          - Optional `target: workflow|artifact-type`.
          - Optional `id` of the target definition.
          - Live language preferences from `owl config show --json` (`settings.language.communication`, `settings.language.artifacts`).

          ## Outputs

          - A new or rewritten `workflow.yaml` or `artifact.yaml` produced through `owl workflow new` / `owl artifact-type new` (optionally with `--force` for edits).
          - A passing `owl workflow validate` / `owl artifact-type validate` confirming the result.
          - A short user-facing summary in `settings.language.communication`.

          ## Workflow

          1. **Pre-flight**: confirm project root and language settings.
             - `owl config show --root . --json` → capture `settings.language.communication` and `settings.language.artifacts` (defaults: `communication` for both).
             - If the user did not supply `mode`/`target`/`id`, ask once: "What do you want to do — create workflow / create artifact-type / edit existing?"

          2. **Mode selection**: dispatch to one of the three workflows below.

          ### Mode A — Create workflow

          1. **Q1 — `id`**: ask for the new workflow id (lowercase snake_case). Refuse anything that does not match `/^[a-z][a-z0-9_]*$/`.
          2. **Q2 — `kind`**: ask `task | composite_task` (default: `task`).
          3. **Q3 — `title`**: ask for a human-readable title (in `settings.language.artifacts`).
          4. **Q4 — `description`**: ask for a one-paragraph description (in `settings.language.artifacts`).
          5. **Q5 — artifacts**: iterative loop. For each artifact: ask `key`, `type` (must exist in `owl artifact-type list` results — if not, suggest running Mode B first), and `storage.path` (default: `{{task.id}}/<key>.md`). Stop the loop when the user says "no more".
          6. **Q6 — steps**: iterative loop. For each step: ask `id`, optional `requires` (comma-separated list of earlier step ids), optional `creates` (comma-separated list of artifact keys declared above), optional `context_file` (default: `<step_id>.context.md`). The skill auto-fills `skill: owl-step-run` for every step unless the user names a different `owl-step-<x>` skill explicitly.
          7. **Q7 — confirm**: show the assembled YAML and ask for confirmation.
          8. **Persist**: pipe the body into `owl workflow new --id <id> --kind <kind> --body -`. On success, run `owl workflow validate <id-or-path> --json`. On `ok: true`, summarize for the user; on failure, surface errors and ask whether to fix interactively (loop back to the relevant Q) or abort.
          9. **Registry reminder**: print "To enable this workflow project-wide, add it to `.owl/workflows.yaml` (see existing entries)."

          ### Mode B — Create artifact-type

          1. **Q1 — `id`**: ask for the new artifact-type id (lowercase snake_case). Refuse anything that does not match `/^[a-z][a-z0-9_]*$/`.
          2. **Q2 — `title`**: ask for a human-readable title (in `settings.language.artifacts`).
          3. **Q3 — `kind`**: ask for the kind (default: `markdown`).
          4. **Q4 — `description`**: one-paragraph description (in `settings.language.artifacts`).
          5. **Q5 — `required_sections`** (constitution 5.16: always English): iterative loop. For each section: ask the English heading text. Reject any input that contains characters outside `[A-Za-z0-9 _\\-]` with an explicit message: "required_sections are part of schema identity and must stay English per constitution 5.16."
          6. **Q6 — `front_matter`**: ask which keys are required (default: `status`, `summary`). For each key ask `type` (string/object/array/boolean/integer/null) and optional `enum`.
          7. **Q7 — `template.body`**: ask for the default template body. The body is written in `settings.language.artifacts`. Headings inside the body should mirror `required_sections` (English) for byte-for-byte validation.
          8. **Q8 — confirm**: show the assembled YAML and ask for confirmation.
          9. **Persist**: pipe the body into `owl artifact-type new --id <id> --body -`. Then write the template body into `templates/default.md` through `owl artifact-type new --id <id> --body -` once more if the user supplied a custom template (otherwise the seeded minimal template is left in place).
          10. **Validate**: `owl artifact-type validate <id-or-path> --json`. On `ok: true`, summarize; on failure, surface errors.

          ### Mode C — Edit existing

          1. **Target**: confirm `target` (`workflow|artifact-type`) and `id`.
          2. **Load**: run `owl <target> show <id> --json`. Parse the `definition` block.
          3. **Present**: show the user a structured overview — for workflows, list `id / kind / title / description / artifacts / steps`; for artifact-types, list `id / title / kind / description / required_sections / front_matter`.
          4. **Delta Q&A**: ask per section "change this? [y/N]". For each `y`, run the matching Mode A or Mode B question(s) and capture the new value.
          5. **Re-assemble**: produce the new full YAML in memory by applying the delta to the parsed body.
          6. **Persist**: pipe the body into `owl <target> new --id <id> --body - --force` (the `--force` flag is required for overwriting).
          7. **Validate**: `owl <target> validate <id-or-path> --json`. On `ok: true`, summarize; on failure, surface errors and offer to fix interactively (loop back to the relevant Q) or abort.

          ## Language Clause (constitution 5.16, 5.17)

          - SKILL.md body is **English** (canonical contract; constitution 5.16).
          - Harness Q&A prompts and the final summary are in `settings.language.communication` (read from `owl config show --json` at the start of every run). If `settings.language.communication` is missing, fall back to English and remind the user to run `owl-init`.
          - YAML content the skill drafts (titles, descriptions, template body) is written in `settings.language.artifacts` (defaults to `communication` when missing).
          - `required_sections` literal headings inside artifact-type YAMLs are **always English** — the skill validates the user's input against `[A-Za-z0-9 _\\-]` and rejects localized strings with an explicit constitution-5.16 reference.

          ## Stop Conditions

          Stop and return control to the user with a concrete decision request when:

          - the project root cannot be detected (no `.owl/`).
          - `owl config show` is missing required language settings — direct the user to `owl-init`.
          - the user supplies an `id` that already exists and Mode A/B is requested without explicit "overwrite" intent — ask whether to switch to Mode C or pick a different id.
          - the `type` field of a workflow artifact references an unknown artifact-type — ask whether to switch into Mode B and create it first, or use a different type.
          - `owl workflow validate` / `owl artifact-type validate` fails twice in a row on the same set of errors — surface the errors and ask the user to fix manually or abort.
          - the user provides a localized string for `required_sections` and refuses to convert it to English — abort with an explicit constitution-5.16 reference.
          - `owl workflow new` / `owl artifact-type new` returns a structured error (`invalid_workflow_id`, `workflow_already_exists`, `workflow_validation_failed`, `artifact_type_already_exists`, `artifact_type_validation_failed`) the skill cannot resolve through one obvious retry.

          ## Verification

          - After a complete Mode A run, `owl workflow validate <id-or-path> --json` returns `{ok: true, valid: true, errors: []}`.
          - After a complete Mode B run, `owl artifact-type validate <id-or-path> --json` returns the same.
          - After a complete Mode C run, the rewritten definition validates AND `owl <target> show <id> --json` reflects the new content.
          - The skill never reads or writes `.owl/workflows/*` or `.owl/artifacts/*` files directly; every state-changing operation goes through `bin/owl`.

          ## Notes

          - `owl workflow new` / `owl artifact-type new` accept the YAML body via `--body -` (stdin). The skill assembles the YAML in memory and pipes it in — there is no granular `set-step` / `set-section` CLI; the new/--force pattern is the contract.
          - `owl workflow new --kind composite_task` seeds with a one-step `decompose` baseline; Mode A typically expands it through Q6 into a full multi-step composite workflow.
          - For `--from` cloning (e.g. "make a new workflow from feature"), use `owl workflow new --id <new-id> --from feature`. The skill may offer this as a shortcut when the user says "start from <existing>".
          - Validate-by-path vs validate-by-id: when a new workflow is not yet registered in `.owl/workflows.yaml`, only `owl workflow validate .owl/workflows/<id>/workflow.yaml` works. The skill uses the source path from the `new` response to validate freshly scaffolded definitions.
          - Registry inclusion (`.owl/workflows.yaml` / `.owl/artifacts.yaml`) is out of scope for this skill (constitution-aligned: ad-hoc experiments should not auto-publish). Direct the user to add the entry manually when they want to make the definition project-wide.
        MD

        OWL_AUTHOR_SLASH = <<~MD
          ---
          description: Author or edit Owl workflow / artifact-type definitions via Q&A (no direct YAML editing).
          ---
          Load skill `owl-author`.

          Use the command arguments as free-form intent (mode, target, id): $ARGUMENTS

          Rules:
          - never edit `.owl/workflows/*` or `.owl/artifacts/*` directly — go through `owl workflow new|validate|show` and `owl artifact-type new|validate|show`.
          - speak `settings.language.communication` (from `owl config show --json`); fall back to English if not set.
          - `required_sections` are always English (constitution 5.16) regardless of `settings.language.artifacts`.
        MD

        def files
          orchestrator_files + task_command_files + owl_cli_files +
            owl_step_run_files + owl_init_files + owl_author_files
        end

        def orchestrator_files
          [
            { relative_path: '.claude/skills/owl-orchestrator/SKILL.md', contents: ORCHESTRATOR_BODY },
            { relative_path: '.claude/commands/owl-orchestrator.md', contents: ORCHESTRATOR_SLASH }
          ]
        end

        def task_command_files
          TASK_COMMANDS.map do |name, body|
            { relative_path: ".claude/commands/#{name}.md", contents: body }
          end
        end

        def owl_cli_files
          [
            { relative_path: '.claude/skills/owl-cli/SKILL.md', contents: OWL_CLI_BODY },
            { relative_path: '.claude/commands/owl-cli.md', contents: OWL_CLI_SLASH }
          ]
        end

        def owl_step_run_files
          [
            { relative_path: '.claude/skills/owl-step-run/SKILL.md', contents: OWL_STEP_RUN_BODY },
            { relative_path: '.claude/commands/owl-step-run.md', contents: OWL_STEP_RUN_SLASH }
          ]
        end

        def owl_init_files
          [
            { relative_path: '.claude/skills/owl-init/SKILL.md', contents: OWL_INIT_BODY },
            { relative_path: '.claude/commands/owl-init.md', contents: OWL_INIT_SLASH }
          ]
        end

        def owl_author_files
          [
            { relative_path: '.claude/skills/owl-author/SKILL.md', contents: OWL_AUTHOR_BODY },
            { relative_path: '.claude/commands/owl-author.md', contents: OWL_AUTHOR_SLASH }
          ]
        end
      end
    end
  end
end
