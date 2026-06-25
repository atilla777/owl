# frozen_string_literal: true

require_relative '../../locks/api'
require_relative '../../result'

module Owl
  module Tasks
    module Internal
      # Serializes every read-modify-write of a single `tasks/<id>/task.yaml`
      # under a repo-scoped `Owl::Locks` lock named "task-<id>".
      #
      # Tracker mutations (set-status / label / dependency / abandon / priority /
      # step-variant / plan-approval) do NOT take the per-task claim lease, so
      # they can race a concurrent step mutation of the SAME task from another
      # session. Each mutator reads the current payload, edits it in memory and
      # writes it back; without serialization two interleaved writers lose one
      # another's edit (last-write-wins). Wrapping the WHOLE read+write of one
      # mutator in this lock turns it atomic against every other mutator of the
      # same task — the read always observes the previous writer's committed
      # state. Different tasks use different lock names, so mutations of distinct
      # tasks still run fully in parallel.
      #
      # Lock ordering is `task-lock -> index-lock`: a wrapped mutator calls
      # `IndexWriter.rebuild` (which takes the "index" lock) from INSIDE its
      # task-lock, so the index lock is always the innermost. No caller ever
      # grabs a task-lock while holding the index lock, so the two-lock chain
      # cannot deadlock. The `Owl::Locks` FileLock is NOT reentrant, so a wrapped
      # block must never invoke another mutator that re-locks the same task
      # (that would self-deadlock until the acquire deadline).
      #
      # `Owl::Locks` acquisition is non-blocking (returns `:lock_held` when the
      # lock is live). To serialize contenders rather than failing one we retry
      # with a short backoff up to a bounded wall-clock deadline; a lock still
      # held past the deadline surfaces the `:lock_held` error.
      module TaskMutationLock
        LOCK_PREFIX = 'task-'
        ACQUIRE_TIMEOUT_SECONDS = 10.0
        RETRY_SLEEP_SECONDS = 0.02

        module_function

        def with_lock(root:, task_id:, locks: Owl::Locks::Api, clock: Time,
                      sleeper: ->(seconds) { sleep(seconds) })
          lock = acquire(root: root, task_id: task_id, locks: locks, clock: clock, sleeper: sleeper)
          return lock if lock.err?

          token = lock.value[:token]
          begin
            yield
          ensure
            locks.release(root: root, name: lock_name(task_id), token: token)
          end
        end

        def lock_name(task_id)
          "#{LOCK_PREFIX}#{task_id}"
        end

        # Blocking acquire built from the non-blocking primitive: retry on a live
        # lock with a small sleep until acquired or the deadline passes.
        def acquire(root:, task_id:, locks:, clock:, sleeper:)
          name = lock_name(task_id)
          deadline = clock.now + ACQUIRE_TIMEOUT_SECONDS
          loop do
            result = locks.acquire(root: root, name: name)
            return result if result.ok?
            return result unless result.code == :lock_held
            return result if clock.now >= deadline

            sleeper.call(RETRY_SLEEP_SECONDS)
          end
        end
      end
    end
  end
end
