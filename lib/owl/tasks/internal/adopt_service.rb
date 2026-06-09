# frozen_string_literal: true

require 'securerandom'
require 'time'

require_relative '../../result'
require_relative '../../steps/api'
require_relative 'claim_paths'
require_relative 'claim_service'
require_relative 'current_pointer'
require_relative 'exclusive_lease'
require_relative 'paths'
require_relative 'task_reader'

module Owl
  module Tasks
    module Internal
      # Forcibly take over a task that another (likely dead) session was
      # working: steal its claim lease, point `current` at it, and reset any
      # half-finished `running` steps back to pending so work can resume cleanly.
      module AdoptService
        module_function

        def adopt(root:, task_id:, token: nil, now: Time.now.utc)
          paths_result = Paths.resolve(root: root)
          return paths_result if paths_result.err?

          paths = paths_result.value
          read = TaskReader.read(tasks_root: paths[:tasks], task_id: task_id)
          return read if read.err?

          resolved_token = resolve_token(token)
          payload = ClaimService.build_lease(
            root: root, task_id: task_id, token: resolved_token, opts: { ttl: nil, label: nil, now: now }
          )
          take_over(root: root, paths: paths, task_id: task_id, token: resolved_token,
                    payload: payload, task_payload: read.value[:payload])
        end

        def take_over(root:, paths:, task_id:, token:, payload:, task_payload:)
          ExclusiveLease.replace(
            path: ClaimPaths.claim_path(local_state_root: paths[:local_state], task_id: task_id),
            payload: payload
          )
          CurrentPointer.write(local_state_root: paths[:local_state], task_id: task_id)

          Result.ok(
            task_id: task_id.to_s,
            token: token,
            reopened: reset_running_steps(root: root, task_id: task_id, task_payload: task_payload),
            expires_at: payload['expires_at']
          )
        end

        def reset_running_steps(root:, task_id:, task_payload:)
          running_step_ids(task_payload).each_with_object([]) do |step_id, reopened|
            result = Owl::Steps::Api.reset(root: root, task_id: task_id, step_id: step_id)
            reopened << step_id if result.ok?
          end
        end

        def running_step_ids(task_payload)
          steps = Array(task_payload['steps'] || task_payload[:steps])
          steps
            .select { |s| s.is_a?(Hash) && (s['status'] || s[:status]).to_s == 'running' }
            .map { |s| (s['id'] || s[:id]).to_s }
        end

        def resolve_token(token)
          token.nil? || token.to_s.empty? ? SecureRandom.uuid : token.to_s
        end
      end
    end
  end
end
