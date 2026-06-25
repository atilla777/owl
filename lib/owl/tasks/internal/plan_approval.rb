# frozen_string_literal: true

require 'time'

require_relative '../../result'
require_relative 'claim_paths'
require_relative 'exclusive_lease'
require_relative 'paths'
require_relative 'task_mutation_lock'
require_relative 'task_reader'
require_relative 'task_writer'

module Owl
  module Tasks
    module Internal
      # Persistent, task-level plan-approval state backing the optional
      # `gate: plan_approved` readiness gate. The approval is recorded under the
      # top-level `plan_approval` key of task.yaml and is bound to the `plan`
      # artifact's content_sha (reusing the same hashing mechanism as step
      # completion) so editing the plan — or reopening the `plan` step, which
      # clears the record explicitly — invalidates a prior approval.
      module PlanApproval
        PLAN_STEP_ID = 'plan'

        module_function

        # Gate is open only when an approval is recorded AND it still matches the
        # current plan content_sha. A nil current sha (no plan artifact) never
        # opens the gate.
        def gate_open?(payload, current_plan_sha)
          record = read(payload)
          return false unless record.is_a?(Hash)
          return false unless truthy?(record['approved'] || record[:approved])
          return false if current_plan_sha.nil?

          (record['plan_sha'] || record[:plan_sha]).to_s == current_plan_sha.to_s
        end

        def read(payload)
          return nil unless payload.is_a?(Hash)

          payload['plan_approval'] || payload[:plan_approval]
        end

        def approve(root:, task_id:, token: nil, now: Time.now.utc)
          paths = Paths.resolve(root: root)
          return paths if paths.err?

          TaskMutationLock.with_lock(root: root, task_id: task_id) do
            locked_approve(root: root, paths: paths.value, task_id: task_id, token: token, now: now)
          end
        end

        def locked_approve(root:, paths:, task_id:, token:, now:)
          read_result = TaskReader.read(tasks_root: paths[:tasks], task_id: task_id)
          return unknown_task(task_id) if read_result.err?

          payload = read_result.value[:payload]
          plan_check = ensure_plan_completed(payload, task_id)
          return plan_check if plan_check

          lease_check = ensure_lease_free(paths: paths, task_id: task_id, token: token, now: now)
          return lease_check if lease_check

          finalize_approval(root: root, paths: paths, task_id: task_id, payload: payload, now: now)
        end

        def status(root:, task_id:)
          paths = Paths.resolve(root: root)
          return paths if paths.err?

          read_result = TaskReader.read(tasks_root: paths.value[:tasks], task_id: task_id)
          return unknown_task(task_id) if read_result.err?

          payload = read_result.value[:payload]
          record = read(payload)
          plan_sha = current_plan_sha(root: root, task_id: task_id)
          Result.ok(
            task_id: task_id.to_s,
            approved: truthy?(record.is_a?(Hash) && (record['approved'] || record[:approved])),
            plan_sha: record.is_a?(Hash) ? (record['plan_sha'] || record[:plan_sha]) : nil,
            gate_open: gate_open?(payload, plan_sha)
          )
        end

        # Drop a recorded approval. Idempotent: a no-op when none is present.
        # Takes `root:` (not `tasks_root:`) so the read-modify-write can run under
        # the per-task mutation lock, consistent with `approve`.
        def clear(root:, task_id:)
          paths = Paths.resolve(root: root)
          return paths if paths.err?

          TaskMutationLock.with_lock(root: root, task_id: task_id) do
            locked_clear(tasks_root: paths.value[:tasks], task_id: task_id)
          end
        end

        def locked_clear(tasks_root:, task_id:)
          read_result = TaskReader.read(tasks_root: tasks_root, task_id: task_id)
          return read_result if read_result.err?

          payload = read_result.value[:payload]
          return Result.ok(task_id: task_id.to_s, cleared: false) unless payload.key?('plan_approval')

          payload.delete('plan_approval')
          TaskWriter.write(tasks_root: tasks_root, task_id: task_id, payload: payload)
          Result.ok(task_id: task_id.to_s, cleared: true)
        end

        # Live content_sha of the `plan` artifact, computed through the same
        # ArtifactShaCollector that step completion uses. Lazy-required to avoid
        # a load-time cycle (Steps depends on Tasks). Returns nil when no single
        # plan sha is available.
        def current_plan_sha(root:, task_id:)
          require_relative '../../steps/internal/artifact_sha_collector'
          sha = Owl::Steps::Internal::ArtifactShaCollector.call(
            root: root, task_id: task_id, step_id: PLAN_STEP_ID
          )
          return nil if sha.err?

          sha.value.is_a?(String) ? sha.value : nil
        end

        def finalize_approval(root:, paths:, task_id:, payload:, now:)
          plan_sha = current_plan_sha(root: root, task_id: task_id)
          return plan_artifact_missing(task_id) if plan_sha.nil?

          existing = read(payload)
          if existing.is_a?(Hash) && truthy?(existing['approved']) && existing['plan_sha'].to_s == plan_sha
            return ok_dto(task_id, existing)
          end

          record = { 'approved' => true, 'plan_sha' => plan_sha, 'approved_at' => now.utc.iso8601 }
          payload['plan_approval'] = record
          TaskWriter.write(tasks_root: paths[:tasks], task_id: task_id, payload: payload)
          ok_dto(task_id, record)
        end

        def ensure_plan_completed(payload, task_id)
          plan = Array(payload['steps']).find do |s|
            s.is_a?(Hash) && (s['id'] || s[:id]).to_s == PLAN_STEP_ID
          end
          return plan_not_completed(task_id, 'missing') if plan.nil?

          status = (plan['status'] || plan[:status]).to_s
          return nil if status == 'done'

          plan_not_completed(task_id, status.empty? ? 'pending' : status)
        end

        def ensure_lease_free(paths:, task_id:, token:, now:)
          path = ClaimPaths.claim_path(local_state_root: paths[:local_state], task_id: task_id)
          read_result = ExclusiveLease.read(path: path)
          return nil if read_result.err?

          existing = read_result.value
          return nil if existing.nil?
          return nil if ExclusiveLease.expired?(existing, now)
          return nil if !token.nil? && existing['claimed_by'].to_s == token.to_s

          lease_held(task_id, existing)
        end

        def ok_dto(task_id, record)
          Result.ok(
            task_id: task_id.to_s,
            plan_approval: {
              approved: truthy?(record['approved'] || record[:approved]),
              plan_sha: record['plan_sha'] || record[:plan_sha],
              approved_at: record['approved_at'] || record[:approved_at]
            }
          )
        end

        def truthy?(value)
          value == true || value.to_s == 'true'
        end

        def unknown_task(task_id)
          Result.err(
            code: :unknown_task,
            message: "Task '#{task_id}' not found.",
            details: { task_id: task_id.to_s }
          )
        end

        def plan_not_completed(task_id, status)
          Result.err(
            code: :plan_not_completed,
            message: "Cannot approve the plan for '#{task_id}': the `plan` step is not done (status: #{status}).",
            details: { task_id: task_id.to_s, plan_status: status }
          )
        end

        def plan_artifact_missing(task_id)
          Result.err(
            code: :plan_artifact_missing,
            message: "Cannot approve the plan for '#{task_id}': no `plan` artifact content_sha is available.",
            details: { task_id: task_id.to_s }
          )
        end

        def lease_held(task_id, existing)
          Result.err(
            code: :lease_held,
            message: "Task '#{task_id}' is claimed by another live session; approve from that session or wait.",
            details: { task_id: task_id.to_s, holder: existing.is_a?(Hash) ? existing['claimed_by'] : nil }
          )
        end
      end
    end
  end
end
