# frozen_string_literal: true

module Owl
  module Workflows
    module Internal
      module SeededSources # rubocop:disable Metrics/ModuleLength
        module_function

        def keys
          SOURCES.keys
        end

        def files
          SOURCES.map do |key, contents|
            {
              relative_path: ".owl/workflows/#{key}/workflow.yaml",
              contents: contents
            }
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
              skill: owl-step-brief
              creates: [brief]
            - id: specify
              skill: owl-step-specify
              requires: [brief]
              creates: [spec]
            - id: design
              skill: owl-step-design
              # Optional step — может быть пропущен через `owl step skip`.
              requires: [specify]
              creates: [design]
            - id: plan
              skill: owl-step-plan
              requires: [specify]
              creates: [tasks]
            - id: apply
              skill: owl-step-apply
              requires: [plan]
            - id: verify
              skill: owl-step-verify
              requires: [apply]
              creates: [verification]
            - id: publish
              skill: owl-step-publish
              requires: [verify]
            - id: archive
              skill: owl-step-archive
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
              skill: owl-step-brief
              creates: [brief]
            - id: specify
              skill: owl-step-specify
              requires: [brief]
              creates: [spec]
            - id: design
              skill: owl-step-design
              # Optional step.
              requires: [specify]
              creates: [design]
            - id: decompose
              skill: owl-step-decompose
              requires: [specify]
              creates: [decomposition]
            - id: coordinate
              skill: owl-step-coordinate
              requires: [decompose]
            - id: aggregate_verify
              skill: owl-step-aggregate_verify
              requires: [coordinate]
              creates: [verification]
            - id: publish
              skill: owl-step-publish
              requires: [aggregate_verify]
            - id: archive
              skill: owl-step-archive
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
              skill: owl-step-plan
              creates: [tasks]
            - id: apply
              skill: owl-step-apply
              requires: [plan]
            - id: verify
              skill: owl-step-verify
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
              skill: owl-step-issue
              creates: [issue]
            - id: patch_plan
              skill: owl-step-patch_plan
              requires: [issue]
              creates: [patch_plan]
            - id: tasks
              skill: owl-step-tasks
              requires: [patch_plan]
              creates: [tasks]
            - id: apply
              skill: owl-step-apply
              requires: [tasks]
            - id: verify
              skill: owl-step-verify
              requires: [apply]
              creates: [verification]
            - id: archive
              skill: owl-step-archive
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
              skill: owl-step-question
            - id: findings
              skill: owl-step-findings
              requires: [question]
              creates: [research_findings]
            - id: options
              skill: owl-step-options
              requires: [findings]
            - id: recommendation
              skill: owl-step-recommendation
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
              skill: owl-step-specify
              creates: [spec]
            - id: plan
              skill: owl-step-plan
              requires: [specify]
              creates: [tasks]
            - id: apply
              skill: owl-step-apply
              requires: [plan]
            - id: verify
              skill: owl-step-verify
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
      end
    end
  end
end
