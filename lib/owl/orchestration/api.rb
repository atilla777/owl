# frozen_string_literal: true

require 'time'

require_relative 'internal/next_action_resolver'

module Owl
  module Orchestration
    # Thin facade for the orchestration domain. Read-only: it advises the next
    # action ("what should the orchestrator do next?") without taking a claim,
    # starting a step, or writing to `.owl/` / `tasks/`.
    module Api
      module_function

      # Resolve the next action for the orchestrator. `task_id: nil` runs the
      # canonical selection ladder (current pointer -> auto-select). Returns
      # `Result::Ok(payload)` whose `action.kind` is one of dispatch_step,
      # handoff_composite, stop_blocked, done, no_available_task; infrastructure
      # failures (e.g. an unreadable workflow) surface as `Result::Err`.
      def next_action(root:, task_id: nil, now: Time.now)
        Internal::NextActionResolver.call(root: root, task_id: task_id, now: now)
      end
    end
  end
end
