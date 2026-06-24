# frozen_string_literal: true

require_relative '../../locks/api'
require_relative '../../result'
require_relative 'index_rebuilder'

module Owl
  module Tasks
    module Internal
      # Serializes every rebuild of `tasks/index.yaml` under the repo-scoped
      # `Owl::Locks` lock named "index".
      #
      # The index is produced by a FULL filesystem scan
      # (`IndexRebuilder.rebuild`), not a read-modify-write, so correctness
      # against concurrent create/archive/delete/rebuild from other sessions is
      # achieved by running the whole scan+write under the lock: each rebuild
      # becomes atomic with respect to every other rebuild and no roster update
      # can be lost.
      #
      # The lock is a LEAF — acquired immediately before the scan+write and
      # released in an `ensure` — so it never nests with the per-task lease /
      # step locks and cannot deadlock a normal single-session chain
      # (create -> ... -> archive), where each operation grabs and drops its own
      # index lock in sequence.
      #
      # `Owl::Locks` (FileLock) acquisition is non-blocking: it returns
      # `:lock_held` immediately when the lock is live. To actually serialize
      # contending writers (rather than failing one of them) we retry with a
      # short backoff up to a bounded wall-clock deadline; only a lock that is
      # still held past the deadline surfaces the `:lock_held` error.
      module IndexWriter
        LOCK_NAME = 'index'
        ACQUIRE_TIMEOUT_SECONDS = 10.0
        RETRY_SLEEP_SECONDS = 0.02

        module_function

        def rebuild(root:, tasks_root:, index_path:, locks: Owl::Locks::Api,
                    clock: Time, sleeper: ->(seconds) { sleep(seconds) })
          lock = acquire(root: root, locks: locks, clock: clock, sleeper: sleeper)
          return lock if lock.err?

          token = lock.value[:token]
          begin
            IndexRebuilder.rebuild(tasks_root: tasks_root, index_path: index_path)
          ensure
            locks.release(root: root, name: LOCK_NAME, token: token)
          end
        end

        # Blocking acquire built from the non-blocking primitive: retry on a live
        # lock with a small sleep until acquired or the deadline passes.
        def acquire(root:, locks:, clock:, sleeper:)
          deadline = clock.now + ACQUIRE_TIMEOUT_SECONDS
          loop do
            result = locks.acquire(root: root, name: LOCK_NAME)
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
