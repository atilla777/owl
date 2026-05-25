# frozen_string_literal: true

require_relative '../../result'
require_relative '../../workflows/api'

module Owl
  module Tasks
    module Internal
      # Single source of truth for the `allowed_children` runtime check on
      # composite parents. Both `child_create` (via ChildCreator) and
      # `create --parent` (via Backends::Filesystem#create) consult this guard
      # so the error envelope is identical across CLI surfaces.
      module AllowedChildrenGuard
        module_function

        # Returns Result.ok(checked: false) when the parent workflow does not
        # declare `allowed_children` (permissive default) or when the parent
        # workflow cannot be resolved (callers handle that elsewhere).
        # Returns Result.ok(checked: true) when the child key is whitelisted.
        # Returns Result.err(code: :child_workflow_not_allowed, ...) otherwise.
        def call(root:, parent_id:, parent_workflow_key:, child_workflow_key:)
          return Result.ok(checked: false) if parent_workflow_key.to_s.empty?

          lookup = Owl::Workflows::Api.find(root: root, key: parent_workflow_key.to_s)
          return Result.ok(checked: false) if lookup.err?

          allowed = extract_allowed(lookup.value)
          return Result.ok(checked: false) unless allowed.is_a?(Array)

          return Result.ok(checked: true) if allowed.include?(child_workflow_key.to_s)

          Result.err(
            code: :child_workflow_not_allowed,
            message: "Child workflow '#{child_workflow_key}' is not allowed under parent workflow " \
                     "'#{parent_workflow_key}'. Allowed: #{allowed.inspect}.",
            details: {
              parent_id: parent_id.to_s,
              parent_workflow_key: parent_workflow_key.to_s,
              child_workflow_key: child_workflow_key.to_s,
              allowed_children: allowed
            }
          )
        end

        def extract_allowed(value)
          source = value.is_a?(Hash) ? value[:source] : nil
          body = source.is_a?(Hash) ? (source[:body] || source['body']) : nil
          return nil unless body.is_a?(Hash)

          body['allowed_children']
        end
      end
    end
  end
end
