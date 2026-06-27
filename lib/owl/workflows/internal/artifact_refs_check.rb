# frozen_string_literal: true

require_relative '../../artifacts/api'

module Owl
  module Workflows
    module Internal
      # Validates that every workflow-declared artifact `type:` resolves to a key
      # present in the project artifact registry.
      #
      # Extracted from WorkflowValidator to keep that module focused; mirrors the
      # StepWhenCheck / StepVariantsCheck sibling-check pattern.
      module ArtifactRefsCheck
        module_function

        def call(body, root)
          declared = body['artifacts']
          return [] unless declared.is_a?(Hash) && root

          available = registry_artifact_keys(root)
          declared.flat_map { |key, descriptor| validate_ref(key, descriptor, available) }
        end

        def validate_ref(key, descriptor, available)
          return [] unless descriptor.is_a?(Hash)

          type_key = descriptor['type']
          return [] if type_key.nil? || available.include?(type_key.to_s)

          [error_at(
            "/artifacts/#{key}/type",
            "Artifact '#{key}' references type '#{type_key}' but that type " \
            'is not declared in the project artifact registry.'
          )]
        end

        def registry_artifact_keys(root)
          listing = Owl::Artifacts::Api.list(root: root)
          return [] if listing.err?

          listing.value.map { |entry| entry[:key].to_s }
        rescue StandardError
          []
        end

        def error_at(path, message)
          { path: path, message: message }
        end
      end
    end
  end
end
