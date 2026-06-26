# frozen_string_literal: true

require_relative '../../result'
require_relative '../../tasks/api'

module Owl
  module Orchestration
    module Internal
      # Read-only task-selection ladder shared by the orchestration layer.
      #
      # The current-pointer step is delegated to `Tasks::Api.current_task_id`
      # so `Instructions`/`Status` reuse the same primitive instead of carrying
      # their own copy; this module adds the auto-select tail on top of it.
      # Nothing here mutates state — no claim is taken.
      module TaskResolver
        module_function

        # Full ladder: explicit task_id -> current pointer -> top dep-aware ready
        # auto-select candidate. Returns a plain hash { task_id:, source:, reason: }
        # where `task_id` is nil (source 'none') when nothing is runnable.
        def resolve(root:, task_id: nil)
          return explicit(task_id) if task_id

          current = Owl::Tasks::Api.current_task_id(root: root)
          return from_current(root: root, task_id: current.value) if current.ok?

          auto_select(root: root)
        end

        def explicit(task_id)
          { task_id: task_id.to_s, source: 'explicit', reason: 'explicit TASK-ID requested' }
        end

        # A current pointer left on a terminal task (legacy/archived/abandoned/
        # done) is treated as "no current task": fall through to auto_select
        # instead of advising work on a dead task. This is the SILENT fallback
        # path; explicit `owl next TASK-X` on a terminal id is rejected upstream
        # (CLI `task_terminal` guard) rather than redirected.
        def from_current(root:, task_id:)
          return auto_select(root: root) if terminal?(root: root, task_id: task_id)

          { task_id: task_id.to_s, source: 'current_pointer', reason: 'resolved from current task pointer' }
        end

        def terminal?(root:, task_id:)
          result = Owl::Tasks::Api.orchestration_terminal?(root: root, task_id: task_id)
          result.ok? && result.value
        end

        # Top of the deps+status-aware ready set — never advises a task whose
        # `blocked_by` deps are incomplete or whose own status is parked/terminal.
        def auto_select(root:)
          available = Owl::Tasks::Api.available(root: root, dep_aware: true)
          top = available.ok? ? Array(available.value[:available]).first : nil
          return none_resolution unless top

          {
            task_id: top['task_id'].to_s,
            source: 'auto_select',
            reason: top['reason'] || 'highest-priority runnable task'
          }
        end

        def none_resolution
          { task_id: nil, source: 'none', reason: 'no current task and no runnable task available' }
        end
      end
    end
  end
end
