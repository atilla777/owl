# frozen_string_literal: true

require_relative '../../../result'
require_relative '../task_reader'

module Owl
  module Tasks
    module Internal
      module Archive
        module ChildReadinessChecker
          ARCHIVE_STEP_ID = 'archive'
          TERMINAL_STATUSES = %w[done skipped].freeze

          module_function

          def call(tasks_root:, task_id:)
            task_result = Owl::Tasks::Internal::TaskReader.read(tasks_root: tasks_root, task_id: task_id)
            return task_result if task_result.err?

            payload = task_result.value[:payload]
            missing = compute_missing(payload: payload)
            Result.ok(task_id: task_id.to_s, ready: missing.empty?, missing_steps: missing)
          end

          def compute_missing(payload:)
            steps = payload['steps'] || payload[:steps] || []
            return [] unless steps.is_a?(Array)

            steps.filter_map do |step|
              next unless step.is_a?(Hash)

              id = (step['id'] || step[:id]).to_s
              next if id.empty? || id == ARCHIVE_STEP_ID

              status = (step['status'] || step[:status] || 'pending').to_s
              next if TERMINAL_STATUSES.include?(status)

              { id: id, status: status }
            end
          end
        end
      end
    end
  end
end
