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
              design:
                source: "artifacts/design/artifact.yaml"
              plan:
                source: "artifacts/plan/artifact.yaml"
              review:
                source: "artifacts/review/artifact.yaml"
              decomposition:
                source: "artifacts/decomposition/artifact.yaml"
              verification:
                source: "artifacts/verification/artifact.yaml"
              spec:
                source: "artifacts/spec/artifact.yaml"
              spec_delta:
                source: "artifacts/spec_delta/artifact.yaml"
          YAML
        end

        def source_files
          SeededSources.files
        end

        def keys
          SeededSources.keys
        end

        def minimal_artifact_seed(id:, title: nil, kind: 'markdown')
          <<~YAML
            id: #{id}
            title: #{title || id}
            kind: #{kind}
            description: TODO — describe this artifact type.
            default_template: templates/default.md

            front_matter:
              type: object
              required: [status, summary]
              properties:
                status:
                  type: string
                  enum: [draft, approved]
                summary:
                  type: string

            validation:
              required_sections:
                - Summary
          YAML
        end

        def minimal_artifact_template
          <<~MARKDOWN
            ---
            status: draft
            summary: TODO — one-line summary.
            ---

            ## Summary

            TODO
          MARKDOWN
        end
      end
    end
  end
end
