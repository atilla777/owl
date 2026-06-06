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

            # `managed: true` marks Owl-shipped types as read-only from the project
            # side (upgrade-safe). Customize by cloning: `owl artifact-type new
            # --from <id> --id <new> --register` (project-owned, managed: false).
            artifacts:
              brief:
                source: "artifacts/brief/artifact.yaml"
                managed: true
              design:
                source: "artifacts/design/artifact.yaml"
                managed: true
              plan:
                source: "artifacts/plan/artifact.yaml"
                managed: true
              review:
                source: "artifacts/review/artifact.yaml"
                managed: true
              decomposition:
                source: "artifacts/decomposition/artifact.yaml"
                managed: true
              verification:
                source: "artifacts/verification/artifact.yaml"
                managed: true
              spec:
                source: "artifacts/spec/artifact.yaml"
                managed: true
              spec_delta:
                source: "artifacts/spec_delta/artifact.yaml"
                managed: true
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
