# frozen_string_literal: true

require 'securerandom'
require 'time'

require_relative '../../config/api'
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
        # Config key for the default lease TTL. Explicit `--ttl` always wins;
        # this is consulted only when no TTL is passed, falling back in turn to
        # `ClaimPaths::DEFAULT_TTL_SECONDS` when the key is absent.
        CLAIM_TTL_KEY = 'settings.concurrency.claim_ttl_seconds'

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

        def heartbeat(root:, task_id:, token:, ttl: nil, now: Time.now.utc)
          paths_result = Paths.resolve(root: root)
          return paths_result if paths_result.err?

          path = ClaimPaths.claim_path(local_state_root: paths_result.value[:local_state], task_id: task_id)
          read = ExclusiveLease.read(path: path)
          return read if read.err?

          existing = read.value
          return lease_lost(task_id) unless owned?(existing, token)

          extend_lease(root: root, path: path, existing: existing, token: token, ttl: ttl, now: now)
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
          payload = build_lease(root: root, task_id: task_id, token: token, opts: opts)
          path = ClaimPaths.claim_path(local_state_root: paths[:local_state], task_id: task_id)
          prior = opts[:steal] ? previous_holder(path: path, now: opts[:now]) : nil
          lease = if opts[:steal]
                    ExclusiveLease.replace(path: path, payload: payload)
                  else
                    ExclusiveLease.acquire(path: path, payload: payload, now: opts[:now])
                  end
          return lease if lease.err?

          running_step = opts[:steal] ? first_running_step(paths: paths, task_id: task_id) : nil
          finalize_claim(root: root, paths: paths, task_id: task_id, token: token, payload: payload,
                         stole_from: prior, running_step: running_step)
        end

        def finalize_claim(root:, paths:, task_id:, token:, payload:, stole_from: nil, running_step: nil)
          CurrentPointer.write(local_state_root: paths[:local_state], task_id: task_id)
          Result.ok(
            task_id: task_id.to_s, token: token, claimed_by: token,
            expires_at: payload['expires_at'], stole_from: stole_from,
            ready_step_ids: ready_step_ids(root: root, task_id: task_id),
            **takeover_hint(task_id: task_id, running_step: running_step)
          )
        end

        # A stolen lease does NOT reset the running step the displaced session
        # left behind — `owl task adopt` does. Surface a non-blocking pointer to
        # it; empty hash when none, so the common response is unchanged.
        def takeover_hint(task_id:, running_step:)
          return {} if running_step.nil?

          {
            running_step: running_step,
            hint: "step '#{running_step}' is running; run `owl task adopt #{task_id}` " \
                  'to take it over and reset the stuck step'
          }
        end

        # Id of the first `running` step in the task, or nil. Task payloads are
        # read from disk YAML, so their step keys are always strings.
        def first_running_step(paths:, task_id:)
          read = TaskReader.read(tasks_root: paths[:tasks], task_id: task_id)
          return nil if read.err?

          step = Array(read.value[:payload]['steps']).find { |s| s.is_a?(Hash) && s['status'].to_s == 'running' }
          step && step['id'].to_s
        end

        # Snapshot of the lease being stolen, surfaced in the claim result so the
        # caller can see whose hold it displaced. Returns nil when there was none.
        def previous_holder(path:, now:)
          read = ExclusiveLease.read(path: path)
          return nil if read.err? || !read.value.is_a?(Hash)

          existing = read.value
          {
            claimed_by: existing['claimed_by'],
            label: existing['label'],
            expired: ExclusiveLease.expired?(existing, now)
          }
        end

        def build_lease(root:, task_id:, token:, opts:)
          ttl_seconds = resolve_ttl(root: root, ttl: opts[:ttl])
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

        # Verify the token still owns the lease before a heartbeat extends it.
        def owned?(existing, token)
          existing.is_a?(Hash) && existing['claimed_by'].to_s == token.to_s
        end

        # Rewrite heartbeat_at/expires_at so a long-running step does not let the
        # lease expire mid-work. The window defaults to the lease's original TTL.
        def extend_lease(root:, path:, existing:, token:, ttl:, now:)
          ttl_seconds = resolve_ttl(root: root, ttl: ttl, fallback: existing['ttl_seconds'])
          payload = existing.merge(
            'heartbeat_at' => now.utc.iso8601,
            'expires_at' => (now + ttl_seconds).utc.iso8601,
            'ttl_seconds' => ttl_seconds
          )
          written = ExclusiveLease.replace(path: path, payload: payload)
          return written if written.err?

          Result.ok(
            task_id: existing['task_id'].to_s,
            token: token,
            expires_at: payload['expires_at'],
            heartbeat_at: payload['heartbeat_at'],
            ttl_seconds: ttl_seconds
          )
        end

        # Resolve the effective TTL: explicit `ttl` wins, then `fallback` (e.g. a
        # lease's own prior TTL), then the configured default, then the constant.
        def resolve_ttl(root:, ttl:, fallback: nil)
          return ttl.to_i if positive_int?(ttl)
          return fallback.to_i if positive_int?(fallback)

          configured = configured_ttl(root: root)
          configured.positive? ? configured : ClaimPaths::DEFAULT_TTL_SECONDS
        end

        def positive_int?(value)
          !value.nil? && value.to_i.positive?
        end

        def configured_ttl(root:)
          result = Owl::Config::Api.read_key(root: root, key: CLAIM_TTL_KEY)
          return 0 if result.err?

          value = result.value[:value]
          value.is_a?(Integer) ? value : value.to_i
        rescue StandardError
          0
        end

        def lease_lost(task_id)
          Result.err(
            code: :lease_lost,
            message: "Lease for #{task_id} is gone or held by another session; re-claim or adopt.",
            details: { task_id: task_id.to_s },
            error_class: :recoverable
          )
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
