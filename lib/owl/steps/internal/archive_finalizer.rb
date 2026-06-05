# frozen_string_literal: true

require_relative '../../result'
require_relative '../../tasks/internal/archive/current_resetter'
require_relative '../../tasks/internal/task_reader'

module Owl
  module Steps
    module Internal
      # Releases the current-task pointer once an archived task's workflow is
      # fully finished. Archival deliberately keeps the pointer alive so the
      # post-archive steps (e.g. `commit_push`) can still run; this is the moment
      # — the final step completing — when the task truly leaves the work zone.
      # A no-op for live tasks and for archived tasks with steps still pending.
      module ArchiveFinalizer
        TERMINAL_STEP_STATUSES = %w[done skipped].freeze

        module_function

        def call(tasks_root:, local_state_root:, task_id:)
          read = Owl::Tasks::Internal::TaskReader.read(tasks_root: tasks_root, task_id: task_id)
          return false unless read.ok?

          payload = read.value[:payload]
          return false unless payload['status'].to_s == 'archived'
          return false unless all_steps_terminal?(payload['steps'])

          Owl::Tasks::Internal::Archive::CurrentResetter.reset_if_matches(
            local_state_root: local_state_root, task_id: task_id
          )
          true
        end

        def all_steps_terminal?(steps)
          return false unless steps.is_a?(Array) && !steps.empty?

          steps.all? { |s| TERMINAL_STEP_STATUSES.include?((s['status'] || 'pending').to_s) }
        end
      end
    end
  end
end
