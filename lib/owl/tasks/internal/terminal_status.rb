# frozen_string_literal: true

require_relative 'task_statuses'

module Owl
  module Tasks
    module Internal
      # Decides whether ORCHESTRATION should refuse to advise work on a task,
      # given its task.yaml payload. This is deliberately stricter than a raw
      # `TaskStatuses::TERMINAL` status check:
      #
      # - `abandoned` (cancelled) → always refuse, regardless of remaining steps.
      #   This is the observed bug: an abandoned task whose `plan` step was still
      #   `ready` leaked a `dispatch_step` advice.
      # - `archived` / `done` → refuse ONLY when the workflow is actually
      #   complete (every step `done`/`skipped`). In the seeded delivery
      #   workflows the `archive` step sets the task status to `archived` and
      #   runs BEFORE the terminal `commit_push` step, so an `archived` task with
      #   a still-pending step is mid-flow, NOT dead, and must stay runnable.
      #
      # The availability/ready scanners keep using the raw `TaskStatuses::TERMINAL`
      # constant (an archived in-flight task is not a NEW auto-selectable task);
      # this finer rule applies only to the explicit-id CLI guard and the
      # current-pointer resolution fallback.
      module TerminalStatus
        WORKFLOW_DONE_STATUSES = %w[done skipped].freeze

        module_function

        def orchestration_terminal?(payload)
          hash = payload.to_h
          status = hash['status'].to_s
          return true if status == 'abandoned'
          return false unless TaskStatuses::TERMINAL.include?(status)

          workflow_complete?(hash)
        end

        def workflow_complete?(hash)
          steps = Array(hash['steps'])
          !steps.empty? && steps.all? do |step|
            step.is_a?(Hash) && WORKFLOW_DONE_STATUSES.include?(step['status'].to_s)
          end
        end
      end
    end
  end
end
