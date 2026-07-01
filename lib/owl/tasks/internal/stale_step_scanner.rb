# frozen_string_literal: true

require_relative '../../result'
require_relative 'claim_service'
require_relative 'paths'
require_relative 'task_reader'

module Owl
  module Tasks
    module Internal
      # Read-only detector for orphaned `running` steps: a step left `running`
      # by a session that died mid-step, detectable because the task still
      # carries a claim lease whose TTL has expired. This is the exact
      # `needs_adopt` condition the orchestration resolver uses, surfaced here
      # repo-wide for `owl doctor`.
      #
      # Deliberately precise: a `running` step whose task has NO lease is a
      # normal single-session in-flight step (Owl leases are optional), so it is
      # NOT flagged — mirroring the orchestrator's interpretation and avoiding
      # false positives on active work. Recovery is `owl task adopt` (reclaims
      # the lease and resets the running step), so this class is report-only —
      # `owl doctor --fix` never auto-mutates a step another session might still
      # own.
      module StaleStepScanner
        module_function

        def scan(root:, now: Time.now.utc)
          paths_result = Paths.resolve(root: root)
          return paths_result if paths_result.err?

          claims_result = ClaimService.claims(root: root, now: now)
          return claims_result if claims_result.err?

          expired = Array(claims_result.value[:claims]).select { |entry| entry[:expired] }
          stale = expired.flat_map { |claim| stale_for(tasks_root: paths_result.value[:tasks], claim: claim) }

          Result.ok(stale_steps: stale)
        end

        def stale_for(tasks_root:, claim:)
          task_id = claim[:task_id].to_s
          read = TaskReader.read(tasks_root: tasks_root, task_id: task_id)
          return [] if read.err?

          running_steps(read.value[:payload]).map do |step|
            {
              task_id: task_id,
              step_id: step['id'].to_s,
              lease: 'expired',
              expires_at: claim[:expires_at],
              suggestion: "owl task adopt #{task_id}"
            }
          end
        end

        def running_steps(payload)
          Array(payload['steps']).select do |step|
            step.is_a?(Hash) && step['status'].to_s == 'running'
          end
        end
      end
    end
  end
end
