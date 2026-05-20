# frozen_string_literal: true

require_relative '../../result'
require_relative '../../steps/api'
require_relative '../../tasks/api'
require_relative '../../workflows/api'
require_relative 'skill_reader'

module Owl
  module Instructions
    module Internal
      module PayloadBuilder
        module_function

        def call(root:, task_id: nil, step_id: nil)
          resolved_task_id = task_id || resolve_current_task_id(root: root)
          return resolved_task_id if resolved_task_id.is_a?(Owl::Result::Err)

          resolved_step_id = pick_step_id(root: root, task_id: resolved_task_id, explicit: step_id)
          return resolved_step_id if resolved_step_id.is_a?(Owl::Result::Err)

          invocation_result = Owl::Steps::Api.invocation(
            root: root, task_id: resolved_task_id, step_id: resolved_step_id
          )
          return invocation_result if invocation_result.err?

          invocation = invocation_result.value
          skill_payload = lookup_skill(
            root: root, invocation: invocation, task_id: resolved_task_id, step_id: resolved_step_id
          )
          return skill_payload if skill_payload.is_a?(Owl::Result::Err)

          Owl::Result.ok(build(invocation, skill_payload))
        end

        def pick_step_id(root:, task_id:, explicit:)
          return explicit if explicit

          ready_result = Owl::Workflows::Api.ready_steps(root: root, task_id: task_id)
          return ready_result if ready_result.err?

          first = ready_result.value[:ready].first
          return first[:id] if first

          Owl::Result.err(
            code: :no_ready_steps,
            message: "Task '#{task_id}' has no ready steps.",
            details: { task_id: task_id.to_s }
          )
        end

        def lookup_skill(root:, invocation:, task_id:, step_id:)
          skill_id = invocation.dig(:step, :skill)
          unless skill_id
            return Owl::Result.err(
              code: :step_skill_missing,
              message: "Step '#{step_id}' does not declare a skill id in the workflow definition.",
              details: { task_id: task_id.to_s, step_id: step_id.to_s }
            )
          end

          result = SkillReader.read(root: root, skill_id: skill_id)
          result.err? ? result : result.value
        end

        def resolve_current_task_id(root:)
          current = Owl::Tasks::Api.current(root: root)
          return current if current.err?

          current.value[:task_id]
        end

        def build(invocation, skill_payload)
          task = invocation[:task]
          step = invocation[:step]
          {
            ok: true,
            task: {
              id: task[:id],
              title: task[:title],
              workflow_key: task[:workflow_key],
              kind: task[:kind]
            },
            step: {
              id: step[:id],
              status: step[:status],
              requires: step[:requires],
              creates: step[:creates]
            },
            skill: skill_payload[:skill],
            invocation: invocation,
            summary: skill_payload[:summary]
          }
        end
      end
    end
  end
end
