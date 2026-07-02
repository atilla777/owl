# frozen_string_literal: true

require_relative '../../step_status'

module Owl
  module Status
    module Internal
      module Constants
        COMPOSITE_KIND = 'composite_task'
        DONE_STATUSES = Owl::StepStatus::DONE_STATUSES
        BLOCKER_STATUSES = Owl::StepStatus::BLOCKING_STATUSES
        # Derived (view-only) status for a composite parent's gated step that is
        # held back until its child tasks finish. Not a stored step status.
        BLOCKED_BY_CHILDREN = 'blocked_by_children'
        DEFAULT_TASK_STATUS = 'todo'
        DEFAULT_STEP_STATUS = 'pending'
      end
    end
  end
end
