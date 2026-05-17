# frozen_string_literal: true

require_relative 'seeded_sources'

module Owl
  module Artifacts
    module Internal
      module DefaultTemplate
        module_function

        def render
          <<~YAML
            schema_version: 1

            artifacts:
              brief:
                source: "artifacts/brief/artifact.yaml"
              spec:
                source: "artifacts/spec/artifact.yaml"
              design:
                source: "artifacts/design/artifact.yaml"
              decomposition:
                source: "artifacts/decomposition/artifact.yaml"
              tasks:
                source: "artifacts/tasks/artifact.yaml"
              verification:
                source: "artifacts/verification/artifact.yaml"
              issue:
                source: "artifacts/issue/artifact.yaml"
              patch_plan:
                source: "artifacts/patch_plan/artifact.yaml"
              research_findings:
                source: "artifacts/research_findings/artifact.yaml"
              recommendation:
                source: "artifacts/recommendation/artifact.yaml"
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
