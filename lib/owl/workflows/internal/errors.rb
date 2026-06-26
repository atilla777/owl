# frozen_string_literal: true

require_relative '../../result'

module Owl
  module Workflows
    module Internal
      # Shared `Result.err` builders for the filesystem workflows backend and its
      # context I/O service. Centralised so the error codes/messages stay
      # byte-stable across the callers that emit them (graph, definition,
      # context_show/set, source resolution).
      module Errors
        module_function

        def workflow_source_missing(workflow_key, source)
          Result.err(
            code: :workflow_source_missing,
            message: "Workflow source for '#{workflow_key}' is not present.",
            details: { key: workflow_key.to_s, source_path: source[:source_path] }
          )
        end

        def step_not_found(workflow_key, step_id)
          Result.err(
            code: :unknown_step,
            message: "Workflow '#{workflow_key}' has no step '#{step_id}'.",
            details: { workflow_key: workflow_key.to_s, step_id: step_id.to_s }
          )
        end

        def unknown_variant(step_id, name, available)
          Result.err(
            code: :unknown_step_variant,
            message: "Step '#{step_id}' has no variant '#{name}' (available: #{available.sort.inspect}).",
            details: { step_id: step_id.to_s, variant: name, available: available.sort }
          )
        end

        def missing_context_file(step_id, scope)
          Result.err(
            code: :step_context_file_undeclared,
            message: "Step '#{step_id}' declares no context_file (#{scope}); " \
                     'add it to the workflow source before setting its body.',
            details: { step_id: step_id.to_s }
          )
        end
      end
    end
  end
end
