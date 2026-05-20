# frozen_string_literal: true

module Owl
  module Status
    module Internal
      module Constants
        COMPOSITE_KIND = 'composite_task'
        DONE_STATUSES = %w[done skipped].freeze
        BLOCKER_STATUSES = %w[blocked failed].freeze
        DEFAULT_TASK_STATUS = 'todo'
        DEFAULT_STEP_STATUS = 'pending'
      end
    end
  end
end
