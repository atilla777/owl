# frozen_string_literal: true

require_relative '../claim_paths'

module Owl
  module Tasks
    module Internal
      module Archive
        # Best-effort removal of a task's claim lease when the task reaches a
        # terminal lifecycle state (archive / abandon / delete). A missing lease
        # is not an error — the task may never have been claimed.
        module ClaimResetter
          module_function

          def delete_if_present(local_state_root:, task_id:)
            path = ClaimPaths.claim_path(local_state_root: local_state_root, task_id: task_id)
            path.delete if path.exist?
            true
          rescue SystemCallError
            false
          end
        end
      end
    end
  end
end
