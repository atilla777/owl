# frozen_string_literal: true

require 'time'

require_relative '../../result'
require_relative 'claim_paths'
require_relative 'exclusive_lease'
require_relative 'index_reader'
require_relative 'paths'
require_relative 'task_statuses'
require_relative 'task_summary'

module Owl
  module Tasks
    module Internal
      # Dependency-aware readiness scan: returns the index entries whose every
      # `blocked_by` dependency is complete, that carry no live claim, and whose
      # own status is ready for work. This is the cross-task counterpart to
      # AvailabilityScanner — `available` stays dependency-blind by design;
      # `ready` is the new dep-aware command. A task whose own status is terminal
      # (done/archived/abandoned) or parked (on_hold/blocked) is excluded from the
      # ready-work pool even when its dependencies are all complete.
      module ReadyScanner
        # A task's own status that takes it out of the ready pool because the
        # work is finished or cancelled. Shared with AvailabilityScanner via the
        # single source of truth in `TaskStatuses::TERMINAL`.
        TERMINAL_STATUSES = TaskStatuses::TERMINAL
        # A task's own status that takes it out of the ready pool — terminal plus
        # the explicitly-parked statuses (on_hold/blocked). These gate the task's
        # OWN readiness only; they say nothing about whether it satisfies another
        # task's dependency (see DEP_COMPLETE_STATUSES).
        NON_READY_STATUSES = (TERMINAL_STATUSES + %w[on_hold blocked]).freeze
        # A dependency status that counts as satisfied. An archived dependency
        # leaves the index entirely, so it surfaces as a missing id and is also
        # treated as complete (see `deps_complete?`).
        DEP_COMPLETE_STATUSES = %w[done archived].freeze

        module_function

        def scan(root:, now: Time.now.utc)
          paths_result = Paths.resolve(root: root)
          return paths_result if paths_result.err?

          index_result = IndexReader.read(index_path: paths_result.value[:index])
          return index_result if index_result.err?

          entries = Array(index_result.value[:tasks])
          status_by_id = status_map(entries)
          ready = entries.select do |entry|
            ready_entry?(entry: entry, status_by_id: status_by_id, paths: paths_result.value, now: now)
          end
          # Sort on the raw entries (string-key `id`), then project each into the
          # unified list-element contract as the final step before returning.
          Result.ok(ready: sort_entries(ready).map { |entry| TaskSummary.project(entry, extra: tracker_extra(entry)) })
        end

        # Tracker fields layered on top of the shared core for `ready`/`list`.
        def tracker_extra(entry)
          {
            'parent_id' => entry['parent_id'],
            'labels' => Array(entry['labels']),
            'blocked_by' => Array(entry['blocked_by']),
            'archived_at' => entry['archived_at']
          }
        end

        def status_map(entries)
          entries.each_with_object({}) do |entry, acc|
            next unless entry.is_a?(Hash)

            acc[entry['id'].to_s] = entry['status'].to_s
          end
        end

        def ready_entry?(entry:, status_by_id:, paths:, now:)
          return false unless entry.is_a?(Hash)
          return false if NON_READY_STATUSES.include?(entry['status'].to_s)
          return false unless deps_complete?(entry, status_by_id)

          !live_claim?(paths: paths, task_id: entry['id'].to_s, now: now)
        end

        # A dependency is complete when its status is terminal-complete OR it is
        # absent from the index (archived out of the roster, or a dangling ref —
        # never crash, never block forever).
        def deps_complete?(entry, status_by_id)
          Array(entry['blocked_by']).all? do |dep|
            dep_status = status_by_id[dep.to_s]
            dep_status.nil? || DEP_COMPLETE_STATUSES.include?(dep_status)
          end
        end

        def live_claim?(paths:, task_id:, now:)
          read = ExclusiveLease.read(
            path: ClaimPaths.claim_path(local_state_root: paths[:local_state], task_id: task_id)
          )
          return false if read.err?

          existing = read.value
          existing.is_a?(Hash) && !ExclusiveLease.expired?(existing, now)
        end

        def sort_entries(entries)
          entries.sort_by { |entry| [-priority_of(entry), entry['created_at'].to_s, entry['id'].to_s] }
        end

        def priority_of(entry)
          raw = entry['priority']
          raw.is_a?(Integer) ? raw : raw.to_i
        end
      end
    end
  end
end
