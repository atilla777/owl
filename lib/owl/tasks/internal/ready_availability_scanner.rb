# frozen_string_literal: true

require 'time'

require_relative '../../result'
require_relative 'availability_scanner'
require_relative 'ready_scanner'

module Owl
  module Tasks
    module Internal
      # Deps+status-aware availability: the intersection of AvailabilityScanner
      # (tasks with at least one ready workflow step and no live claim) with
      # ReadyScanner (tasks whose `blocked_by` deps are all complete and whose
      # own status is ready for work). Neither scanner is a subset of the other —
      # AvailabilityScanner ignores deps/parked status, ReadyScanner ignores
      # whether a workflow step is dispatchable — so a candidate must clear BOTH.
      #
      # The result preserves AvailabilityScanner's candidate hash shape and order,
      # so downstream consumers (claim_first_available, reason rendering) keep
      # working unchanged.
      module ReadyAvailabilityScanner
        module_function

        def scan(root:, now: Time.now.utc)
          available_result = AvailabilityScanner.scan(root: root, now: now)
          return available_result if available_result.err?

          ready_result = ReadyScanner.scan(root: root, now: now)
          return ready_result if ready_result.err?

          ready_ids = ready_id_set(ready_result.value[:ready])
          candidates = Array(available_result.value[:available])
                       .select { |candidate| ready_ids.include?(candidate['task_id'].to_s) }
          Result.ok(available: candidates)
        end

        # Both scanners now emit the unified contract (identity under `task_id`),
        # so the intersection keys off `task_id` on both sides.
        def ready_id_set(entries)
          Array(entries).each_with_object(Set.new) do |entry, acc|
            acc << entry['task_id'].to_s if entry.is_a?(Hash)
          end
        end
      end
    end
  end
end
