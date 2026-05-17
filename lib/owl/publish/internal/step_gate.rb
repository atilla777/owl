# frozen_string_literal: true

require_relative '../../result'
require_relative '../../workflows/api'

module Owl
  module Publish
    module Internal
      module StepGate
        STEP_ID = 'publish'
        ACCEPTABLE_STATUSES = %w[ready done].freeze

        module_function

        def call(root:, task_id:, task_payload:, workflow_body:)
          unless workflow_body.is_a?(Hash) && step_defined?(workflow_body)
            return Result.err(
              code: :no_publishable_step,
              message: "Workflow for task '#{task_id}' has no '#{STEP_ID}' step.",
              details: { task_id: task_id.to_s, step_id: STEP_ID }
            )
          end

          stored = stored_status(task_payload)
          return Result.ok(status: 'done') if stored == 'done'

          ready_result = Owl::Workflows::Api.ready_steps(root: root, task_id: task_id)
          return ready_result if ready_result.err?

          ready_ids = ready_result.value[:ready].map { |s| s[:id].to_s }
          if ready_ids.include?(STEP_ID)
            Result.ok(status: 'ready')
          else
            Result.err(
              code: :publish_step_not_ready,
              message: "Step '#{STEP_ID}' for task '#{task_id}' is not ready or done (current status: #{stored}).",
              details: {
                task_id: task_id.to_s,
                step_id: STEP_ID,
                current_status: stored,
                acceptable_statuses: ACCEPTABLE_STATUSES
              }
            )
          end
        end

        def step_defined?(workflow_body)
          steps = workflow_body['steps'] || workflow_body[:steps]
          return false unless steps.is_a?(Array)

          steps.any? { |s| s.is_a?(Hash) && (s['id'] || s[:id]).to_s == STEP_ID }
        end

        def stored_status(task_payload)
          steps = task_payload['steps'] || task_payload[:steps] || []
          entry = steps.find { |s| s.is_a?(Hash) && (s['id'] || s[:id]).to_s == STEP_ID }
          return 'pending' unless entry

          (entry['status'] || entry[:status] || 'pending').to_s
        end
      end
    end
  end
end
