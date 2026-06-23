# frozen_string_literal: true

require_relative '../../result'
require_relative '../../tasks/api'
require_relative '../../workflows/api'
require_relative 'constants'
require_relative 'views'

module Owl
  module Status
    module Internal
      module Builder
        module_function

        def call(root:, task_id: nil)
          resolved_task_id = task_id || resolve_current_task_id(root: root)
          return resolved_task_id if resolved_task_id.is_a?(Owl::Result::Err)

          inspect_result = Owl::Tasks::Api.inspect(root: root, task_id: resolved_task_id)
          return inspect_result if inspect_result.err?

          payload = inspect_result.value[:payload]
          readiness = readiness_for(root: root, task_id: resolved_task_id)

          Owl::Result.ok(build_payload(
                           root: root, task_id: resolved_task_id, payload: payload,
                           ready_ids: readiness[:ready_ids],
                           blocked_by_children: readiness[:blocked_by_children]
                         ))
        end

        def resolve_current_task_id(root:)
          result = Owl::Tasks::Api.current_task_id(root: root)
          return result if result.err?

          result.value
        end

        def readiness_for(root:, task_id:)
          ready = Owl::Workflows::Api.ready_steps(root: root, task_id: task_id)
          return { ready_ids: [], blocked_by_children: [] } if ready.err?

          {
            ready_ids: ready.value[:ready].map { |entry| entry[:id].to_s },
            blocked_by_children: Array(ready.value[:blocked_by_children]).map(&:to_s)
          }
        end

        def build_payload(root:, task_id:, payload:, ready_ids:, blocked_by_children: [])
          steps = Array(payload['steps'])
          steps_view = steps.map do |step|
            Views.step_view(step, ready_ids: ready_ids, blocked_by_children: blocked_by_children)
          end
          progress = Views.progress_view(steps)
          blockers = steps_view
                     .select { |s| blocker_status?(s[:status]) }
                     .map { |s| { id: s[:id], status: s[:status] } }

          body = {
            ok: true,
            task: Views.task_view(task_id: task_id, payload: payload),
            steps: steps_view,
            progress: progress,
            blockers: blockers
          }

          if payload['kind'].to_s == Constants::COMPOSITE_KIND
            body[:children] = Views.children_view(root: root, parent_id: task_id)
          end

          body
        end

        def blocker_status?(status)
          Constants::BLOCKER_STATUSES.include?(status) || status == Constants::BLOCKED_BY_CHILDREN
        end
      end
    end
  end
end
