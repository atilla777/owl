# frozen_string_literal: true

require 'securerandom'
require 'time'

require_relative '../../result'
require_relative '../../workflows/api'
require_relative 'availability_scanner'
require_relative 'claim_paths'
require_relative 'current_pointer'
require_relative 'exclusive_lease'
require_relative 'paths'
require_relative 'task_reader'

module Owl
  module Tasks
    module Internal
      # Atomic task claiming on top of ExclusiveLease. A claim marks a task as
      # owned by one session for `ttl` seconds; `--next` picks the best runnable
      # task via AvailabilityScanner and retries on contention.
      module ClaimService
        module_function

        def claim(root:, task_id: nil, next_: false, ttl: nil, label: nil, steal: false, now: Time.now.utc)
          paths_result = Paths.resolve(root: root)
          return paths_result if paths_result.err?

          opts = { ttl: ttl, label: label, steal: steal, now: now }
          if !task_id.nil?
            claim_explicit(root: root, paths: paths_result.value, task_id: task_id, opts: opts)
          elsif next_
            claim_next(root: root, paths: paths_result.value, opts: opts)
          else
            invalid_arguments
          end
        end

        def release(root:, task_id:, token:)
          paths_result = Paths.resolve(root: root)
          return paths_result if paths_result.err?

          ExclusiveLease.release(
            path: ClaimPaths.claim_path(local_state_root: paths_result.value[:local_state], task_id: task_id),
            token: token
          )
        end

        def claims(root:, now: Time.now.utc)
          paths_result = Paths.resolve(root: root)
          return paths_result if paths_result.err?

          dir = ClaimPaths.claims_dir(local_state_root: paths_result.value[:local_state])
          Result.ok(claims: list_claims(dir, now))
        end

        def claim_explicit(root:, paths:, task_id:, opts:)
          read = TaskReader.read(tasks_root: paths[:tasks], task_id: task_id)
          return read if read.err?

          attempt_claim(root: root, paths: paths, task_id: task_id, opts: opts)
        end

        def claim_next(root:, paths:, opts:)
          scan = AvailabilityScanner.scan(root: root, now: opts[:now])
          return scan if scan.err?

          candidates = scan.value[:available]
          return no_available_task if candidates.empty?

          claim_first_available(root: root, paths: paths, candidates: candidates, opts: opts)
        end

        def claim_first_available(root:, paths:, candidates:, opts:)
          candidates.each do |candidate|
            attempt = attempt_claim(root: root, paths: paths, task_id: candidate[:task_id], opts: opts)
            return attempt if attempt.ok?
            return attempt unless attempt.code == :lease_held
          end
          no_available_task
        end

        def attempt_claim(root:, paths:, task_id:, opts:)
          token = SecureRandom.uuid
          payload = build_lease(task_id: task_id, token: token, opts: opts)
          path = ClaimPaths.claim_path(local_state_root: paths[:local_state], task_id: task_id)
          lease = if opts[:steal]
                    ExclusiveLease.replace(path: path, payload: payload)
                  else
                    ExclusiveLease.acquire(path: path, payload: payload, now: opts[:now])
                  end
          return lease if lease.err?

          finalize_claim(root: root, paths: paths, task_id: task_id, token: token, payload: payload)
        end

        def finalize_claim(root:, paths:, task_id:, token:, payload:)
          CurrentPointer.write(local_state_root: paths[:local_state], task_id: task_id)
          Result.ok(
            task_id: task_id.to_s,
            token: token,
            claimed_by: token,
            expires_at: payload['expires_at'],
            ready_step_ids: ready_step_ids(root: root, task_id: task_id)
          )
        end

        def build_lease(task_id:, token:, opts:)
          ttl_seconds = ttl_value(opts[:ttl])
          stamp = opts[:now].utc.iso8601
          {
            'schema_version' => ClaimPaths::SCHEMA_VERSION,
            'task_id' => task_id.to_s,
            'claimed_by' => token,
            'claimed_at' => stamp,
            'heartbeat_at' => stamp,
            'expires_at' => (opts[:now] + ttl_seconds).utc.iso8601,
            'ttl_seconds' => ttl_seconds,
            'label' => opts[:label]
          }
        end

        def ttl_value(ttl)
          value = ttl.nil? ? ClaimPaths::DEFAULT_TTL_SECONDS : ttl.to_i
          value.positive? ? value : ClaimPaths::DEFAULT_TTL_SECONDS
        end

        def ready_step_ids(root:, task_id:)
          result = Owl::Workflows::Api.ready_steps(root: root, task_id: task_id)
          return [] if result.err?

          Array(result.value[:ready]).map { |step| step[:id] }
        end

        def list_claims(dir, now)
          return [] unless dir.directory?

          dir.children
             .select { |child| child.file? && child.extname == '.yaml' }
             .filter_map { |path| claim_entry(path, now) }
             .sort_by { |entry| entry[:task_id].to_s }
        end

        def claim_entry(path, now)
          read = ExclusiveLease.read(path: path)
          return nil if read.err? || !read.value.is_a?(Hash)

          existing = read.value
          {
            task_id: existing['task_id'],
            claimed_by: existing['claimed_by'],
            expires_at: existing['expires_at'],
            expired: ExclusiveLease.expired?(existing, now),
            label: existing['label']
          }
        end

        def no_available_task
          Result.err(code: :no_available_task, message: 'No runnable planned tasks.', details: {})
        end

        def invalid_arguments
          Result.err(
            code: :invalid_arguments,
            message: 'Provide a TASK-ID or pass --next to auto-select a task.',
            details: {}
          )
        end
      end
    end
  end
end
