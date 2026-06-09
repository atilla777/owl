# frozen_string_literal: true

require 'time'

require_relative '../../result'
require_relative '../../workflows/api'
require_relative 'claim_paths'
require_relative 'exclusive_lease'
require_relative 'index_reader'
require_relative 'paths'

module Owl
  module Tasks
    module Internal
      # Computes the set of runnable, unclaimed tasks for a repository: active
      # tasks (no terminal status) that carry no live claim and still have at
      # least one ready step. The result is ordered so the first element is the
      # best candidate for `task claim --next` / orchestrator auto-selection.
      module AvailabilityScanner
        module_function

        def scan(root:, now: Time.now.utc)
          paths_result = Paths.resolve(root: root)
          return paths_result if paths_result.err?

          index_result = IndexReader.read(index_path: paths_result.value[:index])
          return index_result if index_result.err?

          available = candidates(root: root, paths: paths_result.value, now: now,
                                 entries: index_result.value[:tasks])
          Result.ok(available: sort_candidates(available))
        end

        def candidates(root:, paths:, now:, entries:)
          active_entries(entries).filter_map do |entry|
            build_candidate(root: root, paths: paths, now: now, entry: entry)
          end
        end

        def active_entries(entries)
          Array(entries).select do |entry|
            entry.is_a?(Hash) && entry['status'].to_s.empty?
          end
        end

        def build_candidate(root:, paths:, now:, entry:)
          task_id = entry['id'].to_s
          return nil if live_claim?(paths: paths, task_id: task_id, now: now)

          ready_ids = ready_step_ids(root: root, task_id: task_id)
          return nil if ready_ids.empty?

          candidate_hash(entry: entry, task_id: task_id, ready_ids: ready_ids)
        end

        def candidate_hash(entry:, task_id:, ready_ids:)
          priority = priority_of(entry)
          {
            task_id: task_id,
            title: entry['title'],
            kind: entry['kind'],
            priority: priority,
            created_at: entry['created_at'],
            ready_step_ids: ready_ids,
            reason: "priority=#{priority}; oldest ready task"
          }
        end

        def live_claim?(paths:, task_id:, now:)
          read = ExclusiveLease.read(
            path: ClaimPaths.claim_path(local_state_root: paths[:local_state], task_id: task_id)
          )
          return false if read.err?

          existing = read.value
          existing.is_a?(Hash) && !ExclusiveLease.expired?(existing, now)
        end

        def ready_step_ids(root:, task_id:)
          result = Owl::Workflows::Api.ready_steps(root: root, task_id: task_id)
          return [] if result.err?

          Array(result.value[:ready]).map { |step| step[:id] }
        end

        def priority_of(entry)
          raw = entry['priority']
          raw.is_a?(Integer) ? raw : raw.to_i
        end

        def sort_candidates(candidates)
          candidates.sort_by { |c| [-c[:priority], c[:created_at].to_s, c[:task_id]] }
        end
      end
    end
  end
end
