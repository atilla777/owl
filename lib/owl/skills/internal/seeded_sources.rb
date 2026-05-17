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
            notes: 'Drive this step with `owl archive TASK-ID --json`. Until Stage 7 atomic archive lands, archiving a composite parent with open children returns `composite_with_open_children`; archive each child first.'
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
          2. Inspect progress: `owl task inspect TASK-ID --json` (Stage 4 adds the friendlier `owl status TASK-ID --json` summary).
          3. Pick the next ready step: `owl task ready-steps TASK-ID --json`. Take the first ready step unless the user named one.
          4. Resolve the step skill: `owl step invocation TASK-ID STEP --json` returns the step id, skill id (`owl-step-<step.id>`), artifact paths, template URIs, and validation rules. Stage 4 adds `owl instructions TASK-ID --step-id STEP --json` which packages this with a human-readable summary.
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
            2. `owl task inspect TASK-ID --json` for the full payload (steps, statuses).
            3. `owl task ready-steps TASK-ID --json` for what is ready to do next.

            Stage 4 (Subtask #105) adds `owl status TASK-ID --json` that combines all three into a single agent-friendly payload — switch to that once available.

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

        def files
          step_files + orchestrator_files + task_command_files
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
