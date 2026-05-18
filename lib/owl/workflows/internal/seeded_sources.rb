# frozen_string_literal: true

require 'yaml'

require_relative 'step_contexts'

module Owl
  module Workflows
    module Internal
      module SeededSources # rubocop:disable Metrics/ModuleLength
        module_function

        def keys
          SOURCES.keys
        end

        def files
          SOURCES.flat_map do |key, contents|
            workflow_entry = {
              relative_path: ".owl/workflows/#{key}/workflow.yaml",
              contents: contents
            }

            [workflow_entry] + context_files_for(key, contents)
          end
        end

        FEATURE = <<~YAML
          id: feature
          kind: task
          title: Feature
          description: Стандартный workflow одиночной фичи.

          artifacts:
            brief:
              type: brief
              storage:
                role: tasks
                path: "{{task.id}}/brief.md"
            spec:
              type: spec
              storage:
                role: tasks
                path: "{{task.id}}/spec.md"
            design:
              type: design
              optional: true
              storage:
                role: tasks
                path: "{{task.id}}/design.md"
            tasks:
              type: tasks
              storage:
                role: tasks
                path: "{{task.id}}/tasks.md"
            verification:
              type: verification
              storage:
                role: tasks
                path: "{{task.id}}/verification.md"

          publishes:
            - from: "{{task.id}}/spec.md"
              to: "{{task.id}}/spec.md"

          steps:
            - id: brief
              skill: owl-step-run
              context_file: brief.context.md
              creates: [brief]
            - id: specify
              skill: owl-step-run
              context_file: specify.context.md
              requires: [brief]
              creates: [spec]
            - id: design
              skill: owl-step-run
              context_file: design.context.md
              requires: [specify]
              creates: [design]
            - id: plan
              skill: owl-step-run
              context_file: plan.context.md
              requires: [specify]
              creates: [tasks]
            - id: apply
              skill: owl-step-run
              context_file: apply.context.md
              requires: [plan]
            - id: verify
              skill: owl-step-run
              context_file: verify.context.md
              requires: [apply]
              creates: [verification]
            - id: publish
              skill: owl-step-run
              context_file: publish.context.md
              requires: [verify]
            - id: archive
              skill: owl-step-run
              context_file: archive.context.md
              requires: [publish]
        YAML

        COMPOSITE_FEATURE = <<~YAML
          id: composite_feature
          kind: composite_task
          title: Composite feature
          description: Workflow для крупной фичи с декомпозицией на child tasks.

          artifacts:
            brief:
              type: brief
              storage:
                role: tasks
                path: "{{task.id}}/brief.md"
            spec:
              type: spec
              storage:
                role: tasks
                path: "{{task.id}}/spec.md"
            design:
              type: design
              optional: true
              storage:
                role: tasks
                path: "{{task.id}}/design.md"
            decomposition:
              type: decomposition
              storage:
                role: tasks
                path: "{{task.id}}/decomposition.md"
            verification:
              type: verification
              storage:
                role: tasks
                path: "{{task.id}}/verification.md"

          publishes:
            - from: "{{task.id}}/spec.md"
              to: "{{task.id}}/spec.md"

          steps:
            - id: brief
              skill: owl-step-run
              context_file: brief.context.md
              creates: [brief]
            - id: specify
              skill: owl-step-run
              context_file: specify.context.md
              requires: [brief]
              creates: [spec]
            - id: design
              skill: owl-step-run
              context_file: design.context.md
              requires: [specify]
              creates: [design]
            - id: decompose
              skill: owl-step-run
              context_file: decompose.context.md
              requires: [specify]
              creates: [decomposition]
            - id: coordinate
              skill: owl-step-run
              context_file: coordinate.context.md
              requires: [decompose]
            - id: aggregate_verify
              skill: owl-step-run
              context_file: aggregate_verify.context.md
              requires: [coordinate]
              creates: [verification]
            - id: publish
              skill: owl-step-run
              context_file: publish.context.md
              requires: [aggregate_verify]
            - id: archive
              skill: owl-step-run
              context_file: archive.context.md
              requires: [publish]
        YAML

        FEATURE_SLICE = <<~YAML
          id: feature_slice
          kind: task
          title: Feature slice
          description: Минимальный slice workflow для child task внутри composite feature.

          artifacts:
            tasks:
              type: tasks
              storage:
                role: tasks
                path: "{{task.id}}/tasks.md"
            verification:
              type: verification
              storage:
                role: tasks
                path: "{{task.id}}/verification.md"

          steps:
            - id: plan
              skill: owl-step-run
              context_file: plan.context.md
              creates: [tasks]
            - id: apply
              skill: owl-step-run
              context_file: apply.context.md
              requires: [plan]
            - id: verify
              skill: owl-step-run
              context_file: verify.context.md
              requires: [apply]
              creates: [verification]
        YAML

        HOTFIX = <<~YAML
          id: hotfix
          kind: task
          title: Hotfix
          description: Workflow для срочных продакшен-фиксов.

          artifacts:
            issue:
              type: issue
              storage:
                role: tasks
                path: "{{task.id}}/issue.md"
            patch_plan:
              type: patch_plan
              storage:
                role: tasks
                path: "{{task.id}}/patch_plan.md"
            tasks:
              type: tasks
              storage:
                role: tasks
                path: "{{task.id}}/tasks.md"
            verification:
              type: verification
              storage:
                role: tasks
                path: "{{task.id}}/verification.md"

          steps:
            - id: issue
              skill: owl-step-run
              context_file: issue.context.md
              creates: [issue]
            - id: patch_plan
              skill: owl-step-run
              context_file: patch_plan.context.md
              requires: [issue]
              creates: [patch_plan]
            - id: tasks
              skill: owl-step-run
              context_file: tasks.context.md
              requires: [patch_plan]
              creates: [tasks]
            - id: apply
              skill: owl-step-run
              context_file: apply.context.md
              requires: [tasks]
            - id: verify
              skill: owl-step-run
              context_file: verify.context.md
              requires: [apply]
              creates: [verification]
            - id: archive
              skill: owl-step-run
              context_file: archive.context.md
              requires: [verify]
        YAML

        RESEARCH = <<~YAML
          id: research
          kind: task
          title: Research
          description: Workflow для исследовательской задачи без кода.

          artifacts:
            research_findings:
              type: research_findings
              storage:
                role: tasks
                path: "{{task.id}}/findings.md"
            recommendation:
              type: recommendation
              storage:
                role: tasks
                path: "{{task.id}}/recommendation.md"

          steps:
            - id: question
              skill: owl-step-run
              context_file: question.context.md
            - id: findings
              skill: owl-step-run
              context_file: findings.context.md
              requires: [question]
              creates: [research_findings]
            - id: options
              skill: owl-step-run
              context_file: options.context.md
              requires: [findings]
            - id: recommendation
              skill: owl-step-run
              context_file: recommendation.context.md
              requires: [options]
              creates: [recommendation]
        YAML

        REFACTOR = <<~YAML
          id: refactor
          kind: task
          title: Refactor
          description: |
            Default workflow для рефакторинг-задачи. Конкретный граф
            рекомендуется фиксировать в спецификации child'а; здесь —
            sensible default: specify → plan → apply → verify.

          artifacts:
            spec:
              type: spec
              storage:
                role: tasks
                path: "{{task.id}}/spec.md"
            tasks:
              type: tasks
              storage:
                role: tasks
                path: "{{task.id}}/tasks.md"
            verification:
              type: verification
              storage:
                role: tasks
                path: "{{task.id}}/verification.md"

          steps:
            - id: specify
              skill: owl-step-run
              context_file: specify.context.md
              creates: [spec]
            - id: plan
              skill: owl-step-run
              context_file: plan.context.md
              requires: [specify]
              creates: [tasks]
            - id: apply
              skill: owl-step-run
              context_file: apply.context.md
              requires: [plan]
            - id: verify
              skill: owl-step-run
              context_file: verify.context.md
              requires: [apply]
              creates: [verification]
        YAML

        SOURCES = {
          'feature' => FEATURE,
          'composite_feature' => COMPOSITE_FEATURE,
          'feature_slice' => FEATURE_SLICE,
          'hotfix' => HOTFIX,
          'research' => RESEARCH,
          'refactor' => REFACTOR
        }.freeze

        def context_files_for(workflow_key, workflow_yaml)
          step_ids = parse_step_ids(workflow_yaml)
          step_ids.map do |step_id|
            {
              relative_path: ".owl/workflows/#{workflow_key}/#{step_id}.context.md",
              contents: StepContexts.render(step_id)
            }
          end
        end

        def parse_step_ids(workflow_yaml)
          parsed = YAML.safe_load(workflow_yaml)
          steps = parsed.is_a?(Hash) ? Array(parsed['steps']) : []
          steps.filter_map { |step| step['id'] }
        end
      end
    end
  end
end
