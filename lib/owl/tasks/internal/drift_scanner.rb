# frozen_string_literal: true

require_relative '../../result'
require_relative 'index_reader'
require_relative 'paths'
require_relative 'task_reader'
require_relative 'task_statuses'
require_relative 'terminal_status'

module Owl
  module Tasks
    module Internal
      # Read-only detector for lifecycle status-drift: a task whose workflow is
      # terminally complete (every step `done`/`skipped`) yet whose explicit
      # task-level `status` is still a non-terminal, safely-promotable value
      # (`open` or `in_progress`). The canonical example is a `quick`-workflow
      # task that ran to its terminal step but never reached an `archive` step,
      # so nothing ever flipped `status` off `open`.
      #
      # This is deliberately narrow — it only reports the `status ↔ steps` drift
      # class and never writes. The `owl doctor --fix` reconciliation path reuses
      # the public `Tasks::Api.set_status` writer; this scanner provides only the
      # candidate list.
      module DriftScanner
        # Task statuses safe to promote to `done`. Explicit human states
        # (`blocked`/`on_hold`) and already-terminal states are excluded.
        PROMOTABLE_STATUSES = %w[open in_progress].freeze

        module_function

        def scan(root:)
          paths_result = Paths.resolve(root: root)
          return paths_result if paths_result.err?

          index_result = IndexReader.read(index_path: paths_result.value[:index])
          return index_result if index_result.err?

          drifted = candidate_entries(index_result.value[:tasks]).filter_map do |entry|
            drift_for(tasks_root: paths_result.value[:tasks], entry: entry)
          end

          Result.ok(drifted: drifted)
        end

        # Non-terminal index entries only: a task already `done`/`archived`/
        # `abandoned` is not a drift candidate (and `done` is the target state,
        # so re-scanning after a fix yields nothing — idempotence).
        def candidate_entries(entries)
          Array(entries).select do |entry|
            entry.is_a?(Hash) && !TaskStatuses::TERMINAL.include?(entry['status'].to_s)
          end
        end

        def drift_for(tasks_root:, entry:)
          read = TaskReader.read(tasks_root: tasks_root, task_id: entry['id'].to_s)
          return nil if read.err?

          payload = read.value[:payload]
          status = payload['status'].to_s
          return nil unless PROMOTABLE_STATUSES.include?(status)
          return nil unless TerminalStatus.workflow_complete?(payload)

          {
            task_id: payload['id'].to_s,
            status: status,
            workflow: workflow_key(payload),
            terminal_step_id: terminal_step_id(payload),
            suggested_status: 'done'
          }
        end

        def workflow_key(payload)
          workflow = payload['workflow']
          workflow.is_a?(Hash) ? workflow['key'].to_s : workflow.to_s
        end

        # The step that no other step `requires` — the workflow sink. Falls back
        # to the last declared step id when the graph has no unique sink (or is
        # otherwise irregular).
        def terminal_step_id(payload)
          steps = Array(payload['steps']).grep(Hash)
          return nil if steps.empty?

          required = steps.flat_map { |step| Array(step['requires']).map(&:to_s) }.to_set
          sink = steps.reverse.find { |step| !required.include?(step['id'].to_s) }
          (sink || steps.last)['id'].to_s
        end
      end
    end
  end
end
