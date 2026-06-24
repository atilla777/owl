# frozen_string_literal: true

require_relative 'seeded_sources'

module Owl
  module Workflows
    module Internal
      module DefaultTemplate
        module_function

        def render
          <<~YAML
            schema_version: 1

            default_workflow: feature

            # `managed: true` marks Owl-shipped workflows as read-only from the
            # project side (upgrade-safe). Customize by cloning: `owl workflow new
            # --from <id> --id <new> --register` (project-owned, managed: false).
            workflows:
              feature:
                enabled: true
                version: "1.0"
                title: Feature
                source: "workflows/feature/workflow.yaml"
                managed: true
              composite_feature:
                enabled: true
                version: "1.0"
                title: Composite feature
                source: "workflows/composite_feature/workflow.yaml"
                managed: true
              hotfix:
                enabled: true
                version: "1.0"
                title: Hotfix
                source: "workflows/hotfix/workflow.yaml"
                managed: true
              refactor:
                enabled: true
                version: "1.0"
                title: Refactor
                source: "workflows/refactor/workflow.yaml"
                managed: true
              quick:
                enabled: true
                version: "1.0"
                title: Quick
                source: "workflows/quick/workflow.yaml"
                managed: true
          YAML
        end

        def source_files
          SeededSources.files
        end

        def keys
          SeededSources.keys
        end

        def minimal_seed(id:, kind: 'task', title: nil)
          case kind.to_s
          when 'composite_task' then composite_task_seed(id, title)
          else task_seed(id, title)
          end
        end

        def task_seed(id, title)
          <<~YAML
            id: #{id}
            kind: task
            title: #{title || id}
            description: TODO — describe this workflow.

            artifacts: {}

            steps:
              - id: main
                skill: owl-step-discussion
                session_type: discussion
                tier: advanced
          YAML
        end

        def composite_task_seed(id, title)
          <<~YAML
            id: #{id}
            kind: composite_task
            title: #{title || id}
            description: TODO — describe this composite workflow.

            artifacts:
              decomposition:
                type: decomposition
                storage:
                  role: tasks
                  path: "{{task.id}}/decomposition.md"

            steps:
              - id: decompose
                skill: owl-step-discussion
                session_type: discussion
                tier: advanced
                creates: [decomposition]
          YAML
        end
      end
    end
  end
end
