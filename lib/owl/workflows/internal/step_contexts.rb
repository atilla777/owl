# frozen_string_literal: true

module Owl
  module Workflows
    module Internal
      module StepContexts # rubocop:disable Metrics/ModuleLength
        module_function

        ENTRIES = {
          'brief' => {
            purpose: <<~TXT.chomp,
              Capture the initial brief for a new Owl task: turn a rough request into a structured
              Контекст / Цель / Acceptance criteria document so later steps have a stable foundation.
            TXT
            when_to_use: <<~TXT.chomp,
              First step of `feature` and `composite_feature` workflows when a task needs a written
              intent record before specifying the solution.
            TXT
            inputs: [
              'Task id (from `owl task current --json` or explicit argument).',
              'Human intent: chat history, ticket, requirements paste.',
              'Any context the requester already shared (links, sketches, conversations).'
            ],
            outputs: [
              '`brief` artifact under `tasks/<TASK-ID>/brief.md` with sections Контекст / Цель / Acceptance criteria.'
            ]
          },
          'specify' => {
            purpose: <<~TXT.chomp,
              Promote a brief (or the task intent) into a full task specification with
              Intent / Acceptance criteria / Non-goals / Open questions / Scope so downstream steps
              can plan and apply without re-asking.
            TXT
            when_to_use: <<~TXT.chomp,
              After `brief` in `feature` / `composite_feature` workflows, or as the first step of
              `refactor`.
            TXT
            inputs: [
              '`brief` artifact (when the workflow has one).',
              'Clarifying chat history and any pinned decisions.'
            ],
            outputs: [
              <<~TXT.chomp
                `spec` artifact under `tasks/<TASK-ID>/spec.md` with the required sections and
                front matter status approved.
              TXT
            ]
          },
          'design' => {
            purpose: <<~TXT.chomp,
              When the spec leaves architectural choices open, produce a design.md with
              Контекст / Решение / Альтернативы / Риски. Optional — skip when the task is simple enough.
            TXT
            when_to_use: <<~TXT.chomp,
              In `feature` / `composite_feature` workflows when the spec has unresolved architectural
              decisions. Skip with `owl step skip TASK-ID design --reason "..."` when the task is
              simple enough.
            TXT
            inputs: [
              '`spec` artifact.',
              'Codebase context for any modules the design touches.'
            ],
            outputs: [
              '`design` artifact under `tasks/<TASK-ID>/design.md`.'
            ],
            notes: <<~TXT.chomp
              This step is optional. If skipping, run `owl step skip TASK-ID design --reason '...'`
              instead of `owl step complete`.
            TXT
          },
          'plan' => {
            purpose: <<~TXT.chomp,
              Break the spec (and optional design) into an ordered tasks checklist so `apply` and
              `verify` know exactly what to do.
            TXT
            when_to_use: <<~TXT.chomp,
              After `specify` (and optional `design`) in `feature` / `feature_slice` /
              `refactor` workflows.
            TXT
            inputs: [
              '`spec` artifact.',
              '`design` artifact when the previous step created one.'
            ],
            outputs: [
              '`tasks` artifact under `tasks/<TASK-ID>/tasks.md` — a checklist of concrete actions to apply.'
            ]
          },
          'apply' => {
            purpose: <<~TXT.chomp,
              Execute the checklist from the `plan` (or `tasks` / `patch_plan`) step — edit / create
              code, run local checks, keep changes scoped to this task.
            TXT
            when_to_use: 'After `plan` in `feature` / `feature_slice` / `hotfix` / `refactor` workflows.',
            inputs: [
              '`tasks` artifact (the checklist).',
              '`spec` (and `design` if present) for context on intent.'
            ],
            outputs: [
              'Repository changes scoped to the task. No KOS-side artifact — the work is in code.'
            ]
          },
          'verify' => {
            purpose: <<~TXT.chomp,
              Run tests / smoke / static checks and record the outcome with Summary / Commands /
              Outcomes so the next step (publish/archive) can rely on a passing baseline.
            TXT
            when_to_use: <<~TXT.chomp,
              After `apply` in `feature` / `feature_slice` / `hotfix` / `refactor` workflows.
              In `composite_feature` use `aggregate_verify` instead.
            TXT
            inputs: [
              'Code changes from `apply`.',
              'Project verification harness (test suites, linters, smoke scripts).'
            ],
            outputs: [
              <<~TXT.chomp
                `verification` artifact under `tasks/<TASK-ID>/verification.md` with status
                (passed/failed/partial) in front matter.
              TXT
            ]
          },
          'publish' => {
            purpose: <<~TXT.chomp,
              Copy approved artifacts (typically `spec.md`) to `docs/<...>/` per the workflow
              `publishes` rules so domain documentation reflects the latest task.
            TXT
            when_to_use: 'After `verify` (or `aggregate_verify`) in workflows that declare a `publishes` block.',
            inputs: [
              'Verified spec / artifacts referenced by the workflow `publishes` rules.'
            ],
            outputs: [
              <<~TXT.chomp,
                Files written under `docs/<...>` per `publishes` rules, with `.backup-<timestamp>`
                siblings when overwriting.
              TXT
              'No KOS artifact — the side effect is the docs files.'
            ],
            notes: <<~TXT.chomp
              Drive this step with `owl publish TASK-ID --json`. Owl honors the `publishes` rules
              declared in the workflow YAML.
            TXT
          },
          'archive' => {
            purpose: <<~TXT.chomp,
              Move `tasks/<TASK-ID>/` into `tasks/archive/<date>-<TASK-ID>-<slug>/`, update
              `tasks/index.yaml`, set the task status to archived.
            TXT
            when_to_use: <<~TXT.chomp,
              Final step of `feature` / `composite_feature` / `hotfix` workflows. For composite
              parents, the archive runs atomically across all children.
            TXT
            inputs: [
              'Completed task with all required workflow steps in done/skipped.'
            ],
            outputs: [
              <<~TXT.chomp
                `tasks/<TASK-ID>/` moved into `tasks/archive/<date>-...`, task.yaml
                `status: archived`, tasks/index.yaml updated.
              TXT
            ],
            notes: <<~TXT.chomp
              Drive this step with `owl archive TASK-ID --json`. Composite parents are archived
              atomically together with all ready children; if any child is not ready, the command
              returns `composite_with_unready_children` and lists the missing steps. Closing this
              step (`owl step complete TASK-ID archive`) is a separate user signal from running
              `owl archive`.
            TXT
          },
          'decompose' => {
            purpose: <<~TXT.chomp,
              Read the brief/spec/design of a `composite_feature` and produce `decomposition.md`
              plus matching child tasks (typically `feature_slice` workflow), wired by `parent_id`.
            TXT
            when_to_use: 'Inside `composite_feature` after `specify` (or optional `design`).',
            inputs: [
              '`spec` artifact.',
              '`design` artifact (optional).'
            ],
            outputs: [
              '`decomposition` artifact under `tasks/<PARENT-ID>/decomposition.md`.',
              <<~TXT.chomp
                New child tasks (created via
                `owl task child create --parent PARENT-ID --workflow feature_slice --title "..."`).
              TXT
            ]
          },
          'coordinate' => {
            purpose: <<~TXT.chomp,
              Track the child task tree, surface readiness / blockers, and signal the orchestrator
              when all children are verified and ready for aggregate verification.
            TXT
            when_to_use: 'Inside `composite_feature` after `decompose`.',
            inputs: [
              'Child task tree (`owl task children PARENT-ID --json`, `owl task aggregate-status PARENT-ID --json`).'
            ],
            outputs: [
              <<~TXT.chomp
                Conversational status update; no KOS artifact. Transitions the composite step from
                `coordinate` to `aggregate_verify` once children finish their `verify` step.
              TXT
            ]
          },
          'aggregate_verify' => {
            purpose: <<~TXT.chomp,
              Collect each child task's `verification.md`, summarize outcomes, and produce the
              parent task's `verification` artifact.
            TXT
            when_to_use: 'Inside `composite_feature` after `coordinate` confirms all children are verified.',
            inputs: [
              "Each child task's `verification` artifact."
            ],
            outputs: [
              '`verification` artifact for the parent (composite) task with rolled-up commands and outcomes.'
            ]
          },
          'issue' => {
            purpose: <<~TXT.chomp,
              Write the incident report with Описание / Симптомы / Воздействие / Затронутые версии
              so the patch plan has a fixed problem statement.
            TXT
            when_to_use: 'First step of `hotfix` workflow.',
            inputs: [
              'Incident report / oncall ticket / observed symptom.'
            ],
            outputs: [
              '`issue` artifact under `tasks/<TASK-ID>/issue.md`.'
            ]
          },
          'patch_plan' => {
            purpose: <<~TXT.chomp,
              Produce `patch_plan.md` with Контекст / План фикса / Тесты / Откат — the surgical plan
              that `apply` will execute.
            TXT
            when_to_use: 'In `hotfix` workflow after `issue`.',
            inputs: [
              '`issue` artifact.'
            ],
            outputs: [
              '`patch_plan` artifact under `tasks/<TASK-ID>/patch_plan.md`.'
            ]
          },
          'tasks' => {
            purpose: <<~TXT.chomp,
              Decompose the patch_plan into ordered concrete tasks that `apply` will execute.
              This is the task-checklist step from the hotfix workflow, not a generic
              task-management skill.
            TXT
            when_to_use: 'In `hotfix` workflow after `patch_plan`.',
            inputs: [
              '`patch_plan` artifact.'
            ],
            outputs: [
              '`tasks` artifact under `tasks/<TASK-ID>/tasks.md` — checklist for `apply`.'
            ],
            notes: <<~TXT.chomp
              Do not confuse with the `plan` step in feature/feature_slice/refactor workflows;
              both create a `tasks` artifact but live in different workflows.
            TXT
          },
          'question' => {
            purpose: 'Frame what the research is trying to answer before gathering data.',
            when_to_use: 'First step of `research` workflow.',
            inputs: [
              'Human research request.'
            ],
            outputs: [
              'Question captured in conversation context (no KOS artifact in the seeded research workflow).'
            ],
            notes: <<~TXT.chomp
              The seeded `research` workflow does not require an artifact for this step. Record the
              question in the task body or in the next-step findings artifact.
            TXT
          },
          'findings' => {
            purpose: 'Investigate, gather data, write `findings.md` with Вопрос / Данные / Выводы.',
            when_to_use: 'In `research` workflow after `question`.',
            inputs: [
              'Research question.',
              'Source material (web, docs, code, conversations).'
            ],
            outputs: [
              '`research_findings` artifact under `tasks/<TASK-ID>/findings.md`.'
            ]
          },
          'options' => {
            purpose: 'Translate findings into a short list of distinct viable options, each with pros / cons.',
            when_to_use: 'In `research` workflow after `findings`.',
            inputs: [
              '`research_findings` artifact.'
            ],
            outputs: [
              'Options notes in conversation context; passed forward to the `recommendation` step.'
            ],
            notes: <<~TXT.chomp
              The seeded `research` workflow does not require an artifact for this step. Capture
              options in the next-step recommendation artifact.
            TXT
          },
          'recommendation' => {
            purpose: <<~TXT.chomp,
              Pick one option (or combination) and justify with
              Вопрос / Рекомендация / Обоснование / Альтернативы.
            TXT
            when_to_use: 'Final step of `research` workflow.',
            inputs: [
              '`research_findings` artifact.',
              'Options notes from the prior step.'
            ],
            outputs: [
              '`recommendation` artifact under `tasks/<TASK-ID>/recommendation.md`.'
            ]
          }
        }.freeze

        def ids
          ENTRIES.keys
        end

        def entry(step_id)
          ENTRIES.fetch(step_id.to_s)
        end

        def render(step_id)
          meta = entry(step_id)
          parts = []
          parts << '# Purpose'
          parts << ''
          parts << meta[:purpose]
          parts << ''
          parts << '## When to use'
          parts << ''
          parts << meta[:when_to_use]
          parts << ''
          parts << '## Inputs'
          parts << ''
          meta[:inputs].each { |item| parts << "- #{item}" }
          parts << ''
          parts << '## Outputs'
          parts << ''
          meta[:outputs].each { |item| parts << "- #{item}" }

          if meta[:notes]
            parts << ''
            parts << '## Notes'
            parts << ''
            parts << meta[:notes]
          end

          "#{parts.join("\n")}\n"
        end
      end
    end
  end
end
