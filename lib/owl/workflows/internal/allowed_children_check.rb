# frozen_string_literal: true

require_relative 'registry_loader'

module Owl
  module Workflows
    module Internal
      # Static-validation helper for the top-level `allowed_children` field on
      # composite workflow bodies. Lives next to WorkflowValidator so that the
      # validator file does not grow past Metrics/ModuleLength while still
      # carrying the canonical error codes.
      #
      # Error codes:
      #   - :allowed_children_on_non_composite — list present on kind != composite_task
      #   - :unknown_workflow — referenced key not registered in .owl/workflows.yaml
      #
      # Referential lookups are skipped silently when root is nil (unit tests,
      # scaffold) so the structural checks remain useful without a project.
      module AllowedChildrenCheck
        module_function

        def call(body, root)
          allowed = body['allowed_children']
          return [] if allowed.nil?
          return [] unless allowed.is_a?(Array)

          if body['kind'].to_s != 'composite_task'
            return [error(
              '/allowed_children',
              "allowed_children is only meaningful when kind: composite_task (got kind: #{body['kind']}).",
              :allowed_children_on_non_composite
            )]
          end

          return [] if root.nil?

          known = registry_keys(root)
          return [] if known.nil?

          allowed.each_with_index.with_object([]) do |(key, idx), errs|
            next unless key.is_a?(String) && !key.empty?
            next if known.include?(key)

            errs << error(
              "/allowed_children/#{idx}",
              "Workflow '#{key}' referenced in allowed_children is not defined in the registry.",
              :unknown_workflow
            )
          end
        end

        def registry_keys(root)
          outcome = RegistryLoader.load(root: root)
          return nil unless outcome[0] == :ok

          outcome[1][:entries].map { |entry| entry[:key].to_s }
        rescue StandardError
          nil
        end

        def error(path, message, code)
          { path: path, message: message, code: code.to_s }
        end
      end
    end
  end
end
