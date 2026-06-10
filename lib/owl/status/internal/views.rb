# frozen_string_literal: true

require_relative '../../result'
require_relative '../../tasks/api'
require_relative 'constants'

module Owl
  module Status
    module Internal
      module Views
        module_function

        def task_view(task_id:, payload:)
          {
            id: task_id.to_s,
            title: payload['title'],
            workflow_key: payload.dig('workflow', 'key'),
            kind: payload['kind'],
            parent_id: payload['parent_id']
          }
        end

        def step_view(step, ready_ids:, blocked_by_children: [])
          step ||= {}
          id = (step['id'] || step[:id]).to_s
          stored_status = (step['status'] || step[:status] || Constants::DEFAULT_STEP_STATUS).to_s
          status = blocked_by_children.include?(id) ? Constants::BLOCKED_BY_CHILDREN : stored_status
          {
            id: id,
            status: status,
            skill: step['skill'] || step[:skill],
            ready: ready_ids.include?(id)
          }
        end

        def progress_view(steps)
          total = steps.size
          done = steps.count do |step|
            status = (step.is_a?(Hash) ? (step['status'] || step[:status]) : nil).to_s
            Constants::DONE_STATUSES.include?(status)
          end
          pct = total.zero? ? 0.0 : ((done * 100.0) / total).round(1)
          { done: done, total: total, pct: pct }
        end

        def children_view(root:, parent_id:)
          list_result = Owl::Tasks::Api.list(root: root)
          return [] if list_result.err?

          tasks = list_result.value[:tasks]
          tasks
            .select { |entry| entry.is_a?(Hash) && entry['parent_id'].to_s == parent_id.to_s }
            .map { |child| child_view(root: root, child_summary: child) }
        end

        def child_view(root:, child_summary:)
          child_id = child_summary['id'].to_s
          inspect_result = Owl::Tasks::Api.inspect(root: root, task_id: child_id)
          if inspect_result.err?
            return {
              id: child_id,
              status: child_summary['status'] || Constants::DEFAULT_TASK_STATUS,
              progress: { done: 0, total: 0, pct: 0.0 }
            }
          end

          payload = inspect_result.value[:payload]
          {
            id: child_id,
            status: payload['status'] || child_summary['status'] || Constants::DEFAULT_TASK_STATUS,
            progress: progress_view(Array(payload['steps']))
          }
        end
      end
    end
  end
end
