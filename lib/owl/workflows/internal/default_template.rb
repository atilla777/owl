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

            workflows:
              feature:
                enabled: true
                version: "1.0"
                title: Feature
                source: "workflows/feature/workflow.yaml"
              composite_feature:
                enabled: true
                version: "1.0"
                title: Composite feature
                source: "workflows/composite_feature/workflow.yaml"
              feature_slice:
                enabled: true
                version: "1.0"
                title: Feature slice
                source: "workflows/feature_slice/workflow.yaml"
              hotfix:
                enabled: true
                version: "1.0"
                title: Hotfix
                source: "workflows/hotfix/workflow.yaml"
              research:
                enabled: true
                version: "1.0"
                title: Research
                source: "workflows/research/workflow.yaml"
              refactor:
                enabled: true
                version: "1.0"
                title: Refactor
                source: "workflows/refactor/workflow.yaml"
          YAML
        end

        def source_files
          SeededSources.files
        end

        def keys
          SeededSources.keys
        end
      end
    end
  end
end
