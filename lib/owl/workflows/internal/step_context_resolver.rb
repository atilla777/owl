# frozen_string_literal: true

require_relative '../../result'

module Owl
  module Workflows
    module Internal
      module StepContextResolver
        module_function

        def call(steps:, backend:, source_dir:)
          resolved = {}

          Array(steps).each do |step|
            next unless step.is_a?(Hash)

            step_id = step_id(step)
            next if step_id.nil? || step_id.empty?

            value_result = resolve_step(step: step, step_id: step_id, backend: backend, source_dir: source_dir)
            return value_result if value_result.err?

            value = value_result.value
            resolved[step_id] = value unless value.nil?
          end

          Result.ok(resolved)
        end

        def resolve_step(step:, step_id:, backend:, source_dir:)
          inline_value = step['context'] || step[:context]
          file_value = step['context_file'] || step[:context_file]

          return conflict_error(step_id) if inline_value && file_value
          return Result.ok(inline_value.to_s) if inline_value
          return Result.ok(nil) if file_value.nil?

          file_str = file_value.to_s
          return invalid_file_error(step_id) if file_str.empty?

          backend.read_step_context(
            source_dir: source_dir,
            step_id: step_id,
            relative_path: file_str
          )
        end

        def conflict_error(step_id)
          Result.err(
            code: :step_context_conflict,
            message: "Step '#{step_id}' defines both 'context' and 'context_file'; choose one.",
            details: {
              step_id: step_id,
              fields: %w[context context_file]
            }
          )
        end

        def invalid_file_error(step_id)
          Result.err(
            code: :invalid_step_context_file,
            message: "Step '#{step_id}' has empty 'context_file'.",
            details: {
              step_id: step_id,
              field: 'context_file'
            }
          )
        end

        def step_id(step)
          raw = step['id'] || step[:id]
          raw&.to_s
        end
      end
    end
  end
end
