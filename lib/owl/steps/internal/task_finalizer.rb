# frozen_string_literal: true

require_relative '../../result'
require_relative '../../tasks/api'
require_relative '../../tasks/internal/archive/current_resetter'
require_relative '../../tasks/internal/task_reader'
require_relative '../../tasks/internal/task_statuses'

module Owl
  module Steps
    module Internal
      # Finalizes a TASK once its workflow is fully finished — i.e. the step
      # being completed was the last non-terminal one, so every step is now
      # `done`/`skipped`. Two finalization shapes share this gate:
      #
      # - A workflow WITHOUT an `archive` step (e.g. `quick`) leaves the task at
      #   a non-terminal status; on the final step we promote it to `done` and
      #   release the current-task pointer.
      # - The seeded delivery workflows reach the `archive` step first, which
      #   sets the status to `archived` while deliberately keeping the pointer
      #   alive so post-archive steps (`commit_push`) can still run. When that
      #   final step completes we only release the pointer — the status stays
      #   `archived` (it is already terminal; do NOT overwrite it to `done`).
      #
      # A no-op when steps are still pending, and for already-terminal
      # (`done`/`abandoned`) tasks — which makes re-completing a `done` step a
      # clean idempotent no-op that never rewrites task.yaml.
      module TaskFinalizer
        TERMINAL_STEP_STATUSES = %w[done skipped].freeze

        module_function

        def call(root:, tasks_root:, local_state_root:, task_id:)
          read = Owl::Tasks::Internal::TaskReader.read(tasks_root: tasks_root, task_id: task_id)
          return false unless read.ok?

          payload = read.value[:payload]
          return false unless all_steps_terminal?(payload['steps'])

          status = payload['status'].to_s
          if Owl::Tasks::Internal::TaskStatuses::TERMINAL.include?(status)
            # Already terminal. Only `archived` still needs its pointer released
            # (the archive step parks it there mid-flow). `done`/`abandoned` are
            # fully finalized already — no-op.
            return false unless status == 'archived'
          else
            # Non-terminal task whose workflow is now done: promote to `done`.
            Owl::Tasks::Api.set_status(root: root, task_id: task_id, status: 'done')
          end

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
