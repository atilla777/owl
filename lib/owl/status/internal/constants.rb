# frozen_string_literal: true

module Owl
  module Status
    module Internal
      module Constants
        COMPOSITE_KIND = 'composite_task'
        DONE_STATUSES = %w[done skipped].freeze
        BLOCKER_STATUSES = %w[blocked failed].freeze
        # Derived (view-only) status for a composite parent's gated step that is
        # held back until its child tasks finish. Not a stored step status.
        BLOCKED_BY_CHILDREN = 'blocked_by_children'
        DEFAULT_TASK_STATUS = 'todo'
        DEFAULT_STEP_STATUS = 'pending'
      end
    end
  end
end
