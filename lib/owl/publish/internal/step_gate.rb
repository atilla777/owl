# frozen_string_literal: true

require_relative '../../result'
require_relative '../../workflows/api'

module Owl
  module Publish
    module Internal
      module StepGate
        # The step that performs publishing is resolved from the workflow
        # rather than hardcoded: a step opts in with `publishes: true`. For
        # backward compatibility a step literally named `publish` is still
        # accepted when no step carries the marker.
        FALLBACK_STEP_ID = 'publish'
        ACCEPTABLE_STATUSES = %w[ready done].freeze

        module_function

        def call(root:, task_id:, task_payload:, workflow_body:)
          step_id = resolve_step_id(workflow_body)
          unless step_id
            return Result.err(
              code: :no_publishable_step,
              message: "Workflow for task '#{task_id}' has no publishing step " \
                       "(declare one with `publishes: true`, or name it '#{FALLBACK_STEP_ID}').",
              details: { task_id: task_id.to_s, step_id: FALLBACK_STEP_ID }
            )
          end

          stored = stored_status(task_payload, step_id)
          return Result.ok(status: 'done', step_id: step_id) if stored == 'done'

          ready_result = Owl::Workflows::Api.ready_steps(root: root, task_id: task_id)
          return ready_result if ready_result.err?

          ready_ids = ready_result.value[:ready].map { |s| s[:id].to_s }
          if ready_ids.include?(step_id)
            Result.ok(status: 'ready', step_id: step_id)
          else
            Result.err(
              code: :publish_step_not_ready,
              message: "Step '#{step_id}' for task '#{task_id}' is not ready or done (current status: #{stored}).",
              details: {
                task_id: task_id.to_s,
                step_id: step_id,
                current_status: stored,
                acceptable_statuses: ACCEPTABLE_STATUSES
              }
            )
          end
        end

        # Resolve the id of the step responsible for publishing: first a step
        # flagged `publishes: true`, otherwise a step named `publish`. Returns
        # nil when the workflow declares neither.
        def resolve_step_id(workflow_body)
          steps = workflow_steps(workflow_body)
          return nil unless steps

          marked = steps.find { |s| s.is_a?(Hash) && (s['publishes'] || s[:publishes]) == true }
          return step_id_of(marked) if marked

          fallback = steps.find { |s| s.is_a?(Hash) && step_id_of(s) == FALLBACK_STEP_ID }
          fallback ? FALLBACK_STEP_ID : nil
        end

        def workflow_steps(workflow_body)
          return nil unless workflow_body.is_a?(Hash)

          steps = workflow_body['steps'] || workflow_body[:steps]
          steps.is_a?(Array) ? steps : nil
        end

        def step_id_of(step)
          (step['id'] || step[:id]).to_s
        end

        def stored_status(task_payload, step_id)
          steps = task_payload['steps'] || task_payload[:steps] || []
          entry = steps.find { |s| s.is_a?(Hash) && step_id_of(s) == step_id }
          return 'pending' unless entry

          (entry['status'] || entry[:status] || 'pending').to_s
        end
      end
    end
  end
end
