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
          ready_ids = ready_step_ids(root: root, task_id: resolved_task_id)

          Owl::Result.ok(build_payload(
                           root: root, task_id: resolved_task_id, payload: payload, ready_ids: ready_ids
                         ))
        end

        def resolve_current_task_id(root:)
          current = Owl::Tasks::Api.current(root: root)
          return current if current.err?

          current.value[:task_id]
        end

        def ready_step_ids(root:, task_id:)
          ready = Owl::Workflows::Api.ready_steps(root: root, task_id: task_id)
          return [] if ready.err?

          ready.value[:ready].map { |entry| entry[:id].to_s }
        end

        def build_payload(root:, task_id:, payload:, ready_ids:)
          steps = Array(payload['steps'])
          steps_view = steps.map { |step| Views.step_view(step, ready_ids: ready_ids) }
          progress = Views.progress_view(steps)
          blockers = steps_view
                     .select { |s| Constants::BLOCKER_STATUSES.include?(s[:status]) }
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
      end
    end
  end
end
