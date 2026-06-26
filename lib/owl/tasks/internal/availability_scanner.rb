# frozen_string_literal: true

require 'time'

require_relative '../../result'
require_relative '../../workflows/api'
require_relative 'claim_paths'
require_relative 'exclusive_lease'
require_relative 'index_reader'
require_relative 'paths'
require_relative 'task_statuses'
require_relative 'task_summary'

module Owl
  module Tasks
    module Internal
      # Computes the set of runnable, unclaimed tasks for a repository: active
      # tasks (no terminal status) that carry no live claim and still have at
      # least one ready step. The result is ordered so the first element is the
      # best candidate for `task claim --next` / orchestrator auto-selection.
      module AvailabilityScanner
        # Statuses that take a task out of the runnable pool. Before explicit
        # task-level status existed, only `archived` / `abandoned` were ever
        # written and a runnable task simply had an empty status; now `open` is
        # the create-time default, so availability keys off this terminal set
        # rather than "status is empty". `done` is terminal (logically finished,
        # not yet archived). The set is shared with ReadyScanner via the single
        # source of truth in `TaskStatuses::TERMINAL`.
        TERMINAL_STATUSES = TaskStatuses::TERMINAL

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
            entry.is_a?(Hash) && !TERMINAL_STATUSES.include?(entry['status'].to_s)
          end
        end

        def build_candidate(root:, paths:, now:, entry:)
          task_id = entry['id'].to_s
          return nil if live_claim?(paths: paths, task_id: task_id, now: now)

          actionable_ids = actionable_step_ids(root: root, task_id: task_id)
          return nil if actionable_ids.empty?

          candidate_hash(entry: entry, ready_ids: actionable_ids)
        end

        # Projects the raw index entry into the unified list-element contract
        # (task_id + core fields) via TaskSummary and layers the ranking-specific
        # extras on top: `ready_step_ids` (steps the task can advance on RIGHT NOW
        # — dispatchable `ready` steps plus `conditional_skip` steps the
        # orchestrator advances via `skip_conditional_step`) and a human `reason`.
        # Going through TaskSummary is what gives `available` the `status` and
        # `workflow` core fields it previously lacked.
        def candidate_hash(entry:, ready_ids:)
          priority = priority_of(entry)
          TaskSummary.project(
            entry,
            extra: {
              'ready_step_ids' => ready_ids,
              'reason' => "priority=#{priority}; oldest ready task"
            }
          )
        end

        def live_claim?(paths:, task_id:, now:)
          read = ExclusiveLease.read(
            path: ClaimPaths.claim_path(local_state_root: paths[:local_state], task_id: task_id)
          )
          return false if read.err?

          existing = read.value
          existing.is_a?(Hash) && !ExclusiveLease.expired?(existing, now)
        end

        # Steps the task can act on now: `ready` (dispatchable) plus
        # `conditional_skip` (false `when:` predicate — the orchestrator advances
        # it via `skip_conditional_step`). A task whose only next move is a
        # conditional skip is still actionable, so it must be auto-selectable.
        # `blocked_by_children` / `awaiting_plan_approval` are waiting, not
        # actionable, so they are deliberately excluded. Both buckets come from
        # the single `ready_steps` call.
        def actionable_step_ids(root:, task_id:)
          result = Owl::Workflows::Api.ready_steps(root: root, task_id: task_id)
          return [] if result.err?

          ready = Array(result.value[:ready]).map { |step| step[:id] }
          conditional = Array(result.value[:conditional_skip]).map { |step| step[:id] }
          ready + conditional
        end

        def priority_of(entry)
          raw = entry['priority']
          raw.is_a?(Integer) ? raw : raw.to_i
        end

        def sort_candidates(candidates)
          candidates.sort_by { |c| [-c['priority'], c['created_at'].to_s, c['task_id']] }
        end
      end
    end
  end
end
