# frozen_string_literal: true

require 'json'

module Owl
  module Skills
    module Internal
      module SeededSources # rubocop:disable Metrics/ModuleLength
        module_function

        STEP_SKILLS = {
          'brief' => {
            description: 'Capture the initial brief for a new Owl task.',
            triggers: ['write a brief', 'owl brief', 'start brief', 'capture intent'],
            purpose: 'Turn a rough request into a structured brief documenting context, goal, and acceptance criteria — the foundation any later spec or plan reads from.',
            when_to_use: 'First step of `feature` and `composite_feature` workflows when a task needs a written intent record before specifying the solution.',
            inputs: [
              'Task id (from `owl task current --json` or explicit argument).',
              'Human intent: chat history, ticket, requirements paste.',
              'Any context the requester already shared (links, sketches, conversations).'
            ],
            outputs: [
              '`brief` artifact under `tasks/<TASK-ID>/brief.md` with sections Контекст / Цель / Acceptance criteria.'
            ],
            workflows: %w[feature composite_feature],
            artifact_type: 'brief'
          },
          'specify' => {
            description: 'Promote a brief into a full task specification.',
            triggers: ['write a spec', 'specify task', 'owl specify'],
            purpose: 'Write the task spec with Intent / Acceptance criteria / Non-goals / Open questions / Scope so downstream steps can plan and apply without re-asking.',
            when_to_use: 'After `brief` in `feature` / `composite_feature` workflows, or as the first step of `refactor`.',
            inputs: [
              '`brief` artifact (when the workflow has one).',
              'Clarifying chat history and any pinned decisions.'
            ],
            outputs: [
              '`spec` artifact under `tasks/<TASK-ID>/spec.md` with the required sections and front matter status approved.'
            ],
            workflows: %w[feature composite_feature refactor],
            artifact_type: 'spec'
          },
          'design' => {
            description: 'Capture an optional design / approach document.',
            triggers: ['owl design', 'design doc', 'approach doc'],
            purpose: 'When the spec leaves architectural choices open, produce a design.md with Контекст / Решение / Альтернативы / Риски. Optional — skip if not needed.',
            when_to_use: 'In `feature` / `composite_feature` workflows when the spec has unresolved architectural decisions. Skip with `owl step skip TASK-ID design --reason "..."` when the task is simple enough.',
            inputs: [
              '`spec` artifact.',
              'Codebase context for any modules the design touches.'
            ],
            outputs: [
              '`design` artifact under `tasks/<TASK-ID>/design.md`.'
            ],
            workflows: %w[feature composite_feature],
            artifact_type: 'design',
            notes: "This step is optional. If skipping, run `owl step skip TASK-ID design --reason '...'` instead of `owl step complete`."
          },
          'plan' => {
            description: 'Plan implementation as an ordered tasks checklist.',
            triggers: ['owl plan', 'task plan', 'implementation plan'],
            purpose: 'Break the spec (and optional design) into an ordered tasks checklist so `apply` and `verify` know exactly what to do.',
            when_to_use: 'After `specify` (and optional `design`) in `feature` / `feature_slice` / `refactor` workflows.',
            inputs: [
              '`spec` artifact.',
              '`design` artifact when the previous step created one.'
            ],
            outputs: [
              '`tasks` artifact under `tasks/<TASK-ID>/tasks.md` — a checklist of concrete actions to apply.'
            ],
            workflows: %w[feature feature_slice refactor],
            artifact_type: 'tasks'
          },
          'apply' => {
            description: 'Apply the implementation plan (write the code).',
            triggers: ['owl apply', 'implement', 'apply plan'],
            purpose: 'Execute the checklist from the `plan` step — edit / create code, run local checks, keep changes scoped to this task.',
            when_to_use: 'After `plan` in `feature` / `feature_slice` / `hotfix` / `refactor` workflows.',
            inputs: [
              '`tasks` artifact (the checklist).',
              '`spec` (and `design` if present) for context on intent.'
            ],
            outputs: [
              'Repository changes scoped to the task. No KOS-side artifact — the work is in code.'
            ],
            workflows: %w[feature feature_slice hotfix refactor]
          },
          'verify' => {
            description: 'Verify the implementation against the spec / plan.',
            triggers: ['owl verify', 'run tests', 'verification report'],
            purpose: 'Run tests / smoke / static checks and record the outcome with Summary / Commands / Outcomes so the next step (publish/archive) can rely on a passing baseline.',
            when_to_use: 'After `apply` in `feature` / `feature_slice` / `hotfix` / `refactor` workflows. In `composite_feature` use `aggregate_verify` instead.',
            inputs: [
              'Code changes from `apply`.',
              'Project verification harness (test suites, linters, smoke scripts).'
            ],
            outputs: [
              '`verification` artifact under `tasks/<TASK-ID>/verification.md` with status (passed/failed/partial) in front matter.'
            ],
            workflows: %w[feature feature_slice hotfix refactor],
            artifact_type: 'verification'
          },
          'publish' => {
            description: 'Publish task artifacts to docs storage per workflow `publishes` rules.',
            triggers: ['owl publish', 'publish docs'],
            purpose: 'Copy approved artifacts (typically `spec.md`) to `docs/<...>/` so domain documentation reflects the latest task.',
            when_to_use: 'After `verify` in `feature` / `composite_feature` workflows that declare a `publishes` block.',
            inputs: [
              'Verified spec / artifacts referenced by the workflow `publishes` rules.'
            ],
            outputs: [
              'Files written under `docs/<...>` per `publishes` rules, with `.backup-<timestamp>` siblings when overwriting.',
              'No KOS artifact — the side effect is the docs files.'
            ],
            workflows: %w[feature composite_feature],
            notes: 'Drive this step with `owl publish TASK-ID --json`. Owl honors the `publishes` rules declared in the workflow YAML.'
          },
          'archive' => {
            description: 'Archive the task at the end of its workflow.',
            triggers: ['owl archive', 'archive task'],
            purpose: 'Move `tasks/<TASK-ID>/` into `tasks/archive/<date>-<TASK-ID>-<slug>/`, update `tasks/index.yaml`, set the task status to archived.',
            when_to_use: 'Final step of `feature` / `composite_feature` / `hotfix` workflows. For composite parents, ensure children are archived first (Stage 7 brings atomic subtree archive).',
            inputs: [
              'Completed task with all required workflow steps in done/skipped.'
            ],
            outputs: [
              '`tasks/<TASK-ID>/` moved into `tasks/archive/<date>-...`, task.yaml `status: archived`, tasks/index.yaml updated.'
            ],
            workflows: %w[feature composite_feature hotfix],
            notes: 'Drive this step with `owl archive TASK-ID --json`. Composite parents are archived atomically together with all ready children; if any child is not ready, the command returns `composite_with_unready_children` and lists the missing steps.'
          },
          'decompose' => {
            description: 'Decompose a composite_task into child task slices.',
            triggers: ['owl decompose', 'split composite', 'break into children'],
            purpose: 'Read the brief/spec/design of a `composite_feature` and produce `decomposition.md` plus matching child tasks (typically `feature_slice` workflow), wired by `parent_id`.',
            when_to_use: 'Inside `composite_feature` after `specify` (or optional `design`).',
            inputs: [
              '`spec` artifact.',
              '`design` artifact (optional).'
            ],
            outputs: [
              '`decomposition` artifact under `tasks/<PARENT-ID>/decomposition.md`.',
              'New child tasks (created with `parent_id = PARENT-ID`).'
            ],
            workflows: %w[composite_feature],
            artifact_type: 'decomposition',
            notes: 'Until Subtask 5 ships `owl task child create`, use `owl task create --parent PARENT-ID --workflow feature_slice --title "..."` manually for each child described in `decomposition.md`.'
          },
          'coordinate' => {
            description: 'Coordinate execution of child tasks for a composite_feature.',
            triggers: ['owl coordinate', 'track children'],
            purpose: 'Track the child task tree, surface readiness / blockers, and signal the orchestrator when all children are verified and ready for aggregate verification.',
            when_to_use: 'Inside `composite_feature` after `decompose`.',
            inputs: [
              'Child task tree (Stage 7 adds `owl task children PARENT-ID --json`; until then use `owl task list --json` and filter by `parent_id`).'
            ],
            outputs: [
              'Conversational status update; no KOS artifact. Transitions the composite step from `coordinate` to `aggregate_verify` once children finish their `verify` step.'
            ],
            workflows: %w[composite_feature]
          },
          'aggregate_verify' => {
            description: 'Aggregate child verification reports into the parent verification report.',
            triggers: ['aggregate verify', 'rollup verification'],
            purpose: 'Collect each child task\'s `verification.md`, summarize outcomes, and produce the parent task\'s `verification` artifact.',
            when_to_use: 'Inside `composite_feature` after `coordinate` confirms all children are verified.',
            inputs: [
              'Each child task\'s `verification` artifact.'
            ],
            outputs: [
              '`verification` artifact for the parent (composite) task with rolled-up commands and outcomes.'
            ],
            workflows: %w[composite_feature],
            artifact_type: 'verification'
          },
          'issue' => {
            description: 'Capture an incident issue at the start of a hotfix.',
            triggers: ['owl issue', 'hotfix issue', 'capture incident'],
            purpose: 'Write the incident report with Описание / Симптомы / Воздействие / Затронутые версии so the patch plan has a fixed problem statement.',
            when_to_use: 'First step of `hotfix` workflow.',
            inputs: [
              'Incident report / oncall ticket / observed symptom.'
            ],
            outputs: [
              '`issue` artifact under `tasks/<TASK-ID>/issue.md`.'
            ],
            workflows: %w[hotfix],
            artifact_type: 'issue'
          },
          'patch_plan' => {
            description: 'Write a patch plan for the captured hotfix issue.',
            triggers: ['patch plan', 'owl patch_plan'],
            purpose: 'Produce `patch_plan.md` with Контекст / План фикса / Тесты / Откат — the surgical plan that `apply` will execute.',
            when_to_use: 'In `hotfix` workflow after `issue`.',
            inputs: [
              '`issue` artifact.'
            ],
            outputs: [
              '`patch_plan` artifact under `tasks/<TASK-ID>/patch_plan.md`.'
            ],
            workflows: %w[hotfix],
            artifact_type: 'patch_plan'
          },
          'tasks' => {
            description: 'Write the per-hotfix task checklist (tasks.md).',
            triggers: ['hotfix tasks', 'owl tasks'],
            purpose: 'Decompose the patch_plan into ordered concrete tasks that `apply` will execute. This is the *task-checklist step from the hotfix workflow*, not a generic task-management skill.',
            when_to_use: 'In `hotfix` workflow after `patch_plan`.',
            inputs: [
              '`patch_plan` artifact.'
            ],
            outputs: [
              '`tasks` artifact under `tasks/<TASK-ID>/tasks.md` — checklist for `apply`.'
            ],
            workflows: %w[hotfix],
            artifact_type: 'tasks',
            notes: 'Do not confuse with the `plan` step in feature/feature_slice/refactor workflows; both create a `tasks` artifact but live in different workflows.'
          },
          'question' => {
            description: 'State the research question to investigate.',
            triggers: ['research question', 'owl question'],
            purpose: 'Frame what the research is trying to answer before gathering data.',
            when_to_use: 'First step of `research` workflow.',
            inputs: [
              'Human research request.'
            ],
            outputs: [
              'Question captured in conversation context (no KOS artifact in the seeded research workflow).'
            ],
            workflows: %w[research],
            notes: 'The seeded `research` workflow does not require an artifact for this step. Record the question in the task body or in the next-step findings artifact.'
          },
          'findings' => {
            description: 'Record research findings.',
            triggers: ['research findings', 'owl findings'],
            purpose: 'Investigate, gather data, write `findings.md` with Вопрос / Данные / Выводы.',
            when_to_use: 'In `research` workflow after `question`.',
            inputs: [
              'Research question.',
              'Source material (web, docs, code, conversations).'
            ],
            outputs: [
              '`research_findings` artifact under `tasks/<TASK-ID>/findings.md`.'
            ],
            workflows: %w[research],
            artifact_type: 'research_findings'
          },
          'options' => {
            description: 'Enumerate candidate options from research findings.',
            triggers: ['research options', 'list options'],
            purpose: 'Translate findings into a short list of distinct viable options, each with pros / cons.',
            when_to_use: 'In `research` workflow after `findings`.',
            inputs: [
              '`research_findings` artifact.'
            ],
            outputs: [
              'Options notes in conversation context; passed forward to the `recommendation` step.'
            ],
            workflows: %w[research],
            notes: 'The seeded `research` workflow does not require an artifact for this step. Capture options in the next-step recommendation artifact.'
          },
          'recommendation' => {
            description: 'Write the final research recommendation.',
            triggers: ['recommendation', 'owl recommend'],
            purpose: 'Pick one option (or combination) and justify with Вопрос / Рекомендация / Обоснование / Альтернативы.',
            when_to_use: 'Final step of `research` workflow.',
            inputs: [
              '`research_findings` artifact.',
              'Options notes from the prior step.'
            ],
            outputs: [
              '`recommendation` artifact under `tasks/<TASK-ID>/recommendation.md`.'
            ],
            workflows: %w[research],
            artifact_type: 'recommendation'
          }
        }.freeze

        ORCHESTRATOR_BODY = <<~MD
          ---
          name: owl-orchestrator
          description: Drive an Owl task through its workflow end-to-end using `owl` CLI as the only source of truth.
          triggers: ["owl orchestrator", "continue owl task", "drive owl workflow", "next owl step"]
          ---

          ## Purpose

          Run an Owl task from its current step to completion. Treat the `owl` CLI as the sole interface to project state — do not read `.owl/` or `tasks/` files directly. Each step has its own skill (`owl-step-<id>`); this orchestrator picks the next ready step and delegates.

          ## When to use

          - The user has a current Owl task and asks to continue / do the next step / names a specific TASK-ID.
          - A new task was just created and is ready for its first step.
          - A previous orchestrator run was interrupted and you need to resume.

          ## Inputs

          - Current task id from `owl task current --json` or an explicit `TASK-XXXX` from the user.
          - Optional step id when the user names one explicitly.

          ## Outputs

          - Each step's artifact written through `owl artifact resolve` + edit + `owl artifact validate`.
          - Step status advanced via `owl step start` / `owl step complete` / `owl step skip`.
          - Final `owl publish` and `owl archive` calls when the workflow declares them.

          ## Workflow

          1. Identify the task: `owl task current --json`. If the user named a different one, switch with `owl task use TASK-ID`.
          2. Inspect progress: `owl status TASK-ID --json` for the agent-friendly summary (steps, progress, blockers, children for composite tasks). Fall back to `owl task inspect TASK-ID --json` when you need the raw task.yaml payload.
          3. Pick the next ready step: `owl task ready-steps TASK-ID --json`. Take the first ready step unless the user named one.
          4. Resolve the step skill: `owl instructions TASK-ID --step-id STEP --json` packages the step invocation with the matching SKILL.md path, slash-command path, and a one-paragraph summary. Use `owl step invocation TASK-ID STEP --json` when you only want the raw invocation block.
          5. Delegate to the matching `owl-step-<step.id>` skill. Its SKILL.md describes the specific work for that step.
          6. After the step:
             - Validate the artifact: `owl artifact validate TASK-ID <artifact_type> --json`.
             - Mark step complete: `owl step complete TASK-ID <step.id>`. Owl runs the validate gate again here.
          7. Repeat from (2) until `owl task ready-steps` returns empty AND the workflow's final step (`archive`) is done.

          ## Notes

          - `owl step skip TASK-ID STEP --reason "..."` is allowed for optional steps (e.g., `design` in `feature` workflow).
          - For `composite_feature` tasks: `decompose` spawns children, `coordinate` tracks them, `aggregate_verify` rolls up. Stage 5 adds `owl task tree / children / parent / aggregate-status` and `owl task child create`.
          - Never read filesystem state directly — always go through `owl ...` CLI. This is an architectural invariant of Owl (Stage 11).
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
            3. Dispatch to `/owl-orchestrator` with that TASK-ID + step hint so the right `owl-step-<id>` skill executes.

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

          `owl-cli` is the shared technical skill for calling `bin/owl` from other Owl-owned skills (`owl-orchestrator`, `owl-step-*`, future `owl-step-run`).

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

          Do not use this skill to decide what workflow stage runs next, what spec to write, whether an artifact is semantically correct, or whether to commit/push. Those decisions belong to the orchestrator and to the step-specific skills.

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

          - `owl init` — materialise `.owl/`, seeded workflows, seeded skills (`owl-step-*`, `owl-orchestrator`, `owl-cli`, `owl-task-*` slash commands), and starter artifact templates. Use `--force` to overwrite previously materialised files.
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
          - `owl step show TASK-ID STEP-ID --json` — merged step + context + artifact_template + task bundle (preferred for new step-run skills).
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

        def files
          step_files + orchestrator_files + task_command_files + owl_cli_files
        end

        def step_skill_ids
          STEP_SKILLS.keys.map { |id| "owl-step-#{id}" }
        end

        def step_files
          STEP_SKILLS.flat_map do |id, meta|
            skill_id = "owl-step-#{id}"
            [
              {
                relative_path: ".claude/skills/#{skill_id}/SKILL.md",
                contents: render_skill_md(id, meta)
              },
              {
                relative_path: ".claude/commands/#{skill_id}.md",
                contents: render_step_slash_command(skill_id, meta)
              }
            ]
          end
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

        def render_skill_md(id, meta)
          skill_id = "owl-step-#{id}"
          frontmatter = <<~FM.strip
            ---
            name: #{skill_id}
            description: #{meta[:description]}
            triggers: #{meta[:triggers].to_json}
            ---
          FM

          body = []
          body << '## Purpose'
          body << ''
          body << meta[:purpose]
          body << ''
          body << '## When to use'
          body << ''
          body << meta[:when_to_use]
          body << ''
          body << '## Inputs'
          body << ''
          meta[:inputs].each { |item| body << "- #{item}" }
          body << ''
          body << '## Outputs'
          body << ''
          meta[:outputs].each { |item| body << "- #{item}" }
          body << ''
          body << '## Workflow'
          body << ''
          body << workflow_steps_for(id, meta).map { |line| line.to_s }.join("\n")

          if meta[:notes]
            body << ''
            body << '## Notes'
            body << ''
            body << meta[:notes]
          end

          "#{frontmatter}\n\n#{body.join("\n")}\n"
        end

        def workflow_steps_for(step_id, meta)
          artifact = meta[:artifact_type]
          steps = []
          steps << "1. Inspect the step: `owl step invocation TASK-ID #{step_id} --json`. The JSON gives you the artifact paths, template URIs, validation rules, and the matching skill id."
          steps << "2. Mark the step started: `owl step start TASK-ID #{step_id}`."
          if artifact
            steps << "3. Resolve the artifact destination: `owl artifact resolve TASK-ID #{artifact} --json`. Write the artifact contents at the returned path, following the template's required sections and front matter schema."
            steps << "4. Validate: `owl artifact validate TASK-ID #{artifact} --json`. Fix structural issues until validation passes."
            steps << "5. Complete the step: `owl step complete TASK-ID #{step_id}`. Owl re-runs the validate gate here as a safety net."
          else
            steps << "3. Do the step's work (see Outputs). Some steps have no artifact — the side effect is in code (`apply`) or in a CLI call (`publish`, `archive`)."
            steps << "4. Complete the step: `owl step complete TASK-ID #{step_id}`."
          end
          steps
        end

        def render_step_slash_command(skill_id, meta)
          <<~MD
            ---
            description: #{meta[:description]}
            ---
            Load skill `#{skill_id}`.

            Use the command arguments as task/step context: $ARGUMENTS

            Rules:
            - if no TASK-ID supplied, use `owl task current --json` to resolve it.
            - drive the step through `owl step invocation` → produce artifact → `owl artifact validate` → `owl step complete`.
            - never read `.owl/` or `tasks/` directly — go through `owl ...` CLI.
          MD
        end
      end
    end
  end
end
