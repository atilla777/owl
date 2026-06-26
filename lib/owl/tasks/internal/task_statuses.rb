# frozen_string_literal: true

module Owl
  module Tasks
    module Internal
      # Single source of truth for TASK-level terminal statuses. A task in one
      # of these states is logically finished or cancelled and must not leak
      # back into orchestration (auto-select, ready/availability scans, the
      # current-pointer resolution ladder).
      #
      # This is deliberately distinct from the STEP-level terminal set in
      # `Internal::Archive::CompletionGate` (`%w[done skipped]`), which gates
      # the archive readiness of individual workflow steps — a different
      # concept that is NOT unified here.
      module TaskStatuses
        TERMINAL = %w[archived abandoned done].freeze
      end
    end
  end
end
