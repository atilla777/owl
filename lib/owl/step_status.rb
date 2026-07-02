# frozen_string_literal: true

module Owl
  # Single source of truth for the step-status vocabulary shared across the
  # status, orchestration and CLI layers: which statuses count as
  # progress-complete or as a blocker, the ASCII status markers, and the
  # progress-bar glyphs. These sets were previously duplicated verbatim in
  # `Owl::Status::Internal::Constants`, the two `workflow_diagram_*` CLI
  # commands, and `Owl::Orchestration::Internal::NextActionResolver`; extracting
  # them here is strictly behaviour-preserving — the values are unchanged.
  module StepStatus
    # A step status that counts as progress-complete: `done`, or intentionally
    # `skipped`. Drives progress counters and the "all steps done" check.
    DONE_STATUSES = %w[done skipped].freeze

    # A step status that marks the step as a blocker needing attention.
    BLOCKING_STATUSES = %w[blocked failed].freeze

    # ASCII status markers, shared by `owl workflow show` and `owl overview`.
    MARK_DONE = '[✓]'
    MARK_CURRENT = '[▶]'
    MARK_PENDING = '[ ]'
    MARK_SKIPPED = '[~]'
    MARK_BLOCKED = '[!]'

    # Progress-bar glyphs and width.
    PROGRESS_WIDTH = 10
    PROGRESS_FILLED = '━'
    PROGRESS_EMPTY = '·'
  end
end
