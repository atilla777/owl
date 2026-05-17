# frozen_string_literal: true

require_relative '../../result'
require_relative '../../validation/api'
require_relative '../../workflows/api'

module Owl
  module Steps
    module Internal
      module OutputValidator
        module_function

        def call(root:, task_id:, step_id:)
          creates_result = collect_creates(root: root, task_id: task_id, step_id: step_id)
          return creates_result if creates_result.err?

          creates = creates_result.value
          return Result.ok([]) if creates.empty?

          results = creates.map { |key| validate_one(root: root, task_id: task_id, key: key) }
          invalid_keys = results.reject { |r| r[:valid] }.map { |r| r[:artifact_key] }
          return Result.ok(results) if invalid_keys.empty?

          Result.err(
            code: :step_outputs_invalid,
            message: "Step '#{step_id}' has invalid output artifacts: #{invalid_keys.join(', ')}.",
            details: { task_id: task_id.to_s, step_id: step_id.to_s, results: results }
          )
        end

        def collect_creates(root:, task_id:, step_id:)
          ready = Owl::Workflows::Api.ready_steps(root: root, task_id: task_id)
          return Result.ok([]) if ready.err?

          definition = Owl::Workflows::Api.definition(root: root, workflow_key: ready.value[:workflow_key])
          return Result.ok([]) if definition.err?

          step = definition.value[:steps][step_id.to_s] || {}
          Result.ok(Array(step['creates'] || step[:creates]))
        end

        def validate_one(root:, task_id:, key:)
          outcome = Owl::Validation::Api.artifact(root: root, task_id: task_id, artifact_key: key)
          if outcome.err?
            {
              artifact_key: key.to_s,
              valid: false,
              violations: [{
                type: 'resolution_error',
                level: 'error',
                description: outcome.message,
                code: outcome.code.to_s
              }]
            }
          else
            {
              artifact_key: outcome.value[:artifact_key],
              valid: outcome.value[:valid],
              violations: outcome.value[:violations]
            }
          end
        end
      end
    end
  end
end
