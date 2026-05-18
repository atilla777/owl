# frozen_string_literal: true

require_relative '../../../result'

module Owl
  module Tasks
    module Internal
      module Archive
        module CompletionGate
          PUBLISH_STEP_ID = 'publish'
          TERMINAL_STATUSES = %w[done skipped].freeze

          module_function

          def call(workflow_body:, task_payload:)
            step_ids = workflow_step_ids(workflow_body)
            statuses = task_step_statuses(task_payload)
            incomplete = collect_incomplete(step_ids, statuses)
            publish_status = statuses[PUBLISH_STEP_ID]
            publish_needs_done = publish_required?(workflow_body, publish_status)

            publish_only_incomplete =
              incomplete.length == 1 && incomplete.first[:id] == PUBLISH_STEP_ID && publish_needs_done
            return publish_required_err(publish_status) if publish_only_incomplete
            return workflow_incomplete_err(incomplete) unless incomplete.empty?
            return publish_required_err(publish_status) if publish_needs_done && publish_status != 'done'

            Result.ok({})
          end

          def workflow_incomplete_err(incomplete)
            Result.err(
              code: :workflow_incomplete,
              message: "Task cannot be archived: #{incomplete.length} step(s) are not done or skipped.",
              details: { incomplete_steps: incomplete }
            )
          end

          def publish_required_err(publish_status)
            Result.err(
              code: :publish_required,
              message: "Task cannot be archived: '#{PUBLISH_STEP_ID}' step is required but is '#{publish_status}'.",
              details: { publish_status: publish_status }
            )
          end

          def workflow_step_ids(workflow_body)
            steps = workflow_body.is_a?(Hash) ? (workflow_body['steps'] || workflow_body[:steps] || []) : []
            return [] unless steps.is_a?(Array)

            steps.filter_map do |step|
              next unless step.is_a?(Hash)

              (step['id'] || step[:id])&.to_s
            end
          end

          def task_step_statuses(task_payload)
            steps = extract_steps(task_payload)
            steps.each_with_object({}) do |step, memo|
              next unless step.is_a?(Hash)

              id = step_id(step)
              next if id.empty?

              memo[id] = step_status(step)
            end
          end

          def extract_steps(task_payload)
            return [] unless task_payload.is_a?(Hash)

            steps = task_payload['steps'] || task_payload[:steps]
            steps.is_a?(Array) ? steps : []
          end

          def step_id(step)
            (step['id'] || step[:id]).to_s
          end

          def step_status(step)
            (step['status'] || step[:status] || 'pending').to_s
          end

          def collect_incomplete(step_ids, statuses)
            step_ids.filter_map do |id|
              status = statuses[id] || 'pending'
              next if TERMINAL_STATUSES.include?(status)

              { id: id, status: status }
            end
          end

          def publish_required?(workflow_body, publish_status)
            step_ids = workflow_step_ids(workflow_body)
            return false unless step_ids.include?(PUBLISH_STEP_ID)

            publish_status != 'skipped'
          end
        end
      end
    end
  end
end
