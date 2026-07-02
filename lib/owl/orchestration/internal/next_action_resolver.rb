# frozen_string_literal: true

require 'time'

require_relative '../../result'
require_relative '../../step_status'
require_relative '../../tasks/api'
require_relative '../../workflows/api'
require_relative 'task_resolver'

module Owl
  module Orchestration
    module Internal
      # Read-only next-action resolver. Composes the existing Tasks / Workflows
      # domain APIs to answer "what should the orchestrator do next?" with a
      # single discriminated `action.kind`. Never mutates state: no claim, no
      # step start, no writes to `.owl/` or `tasks/`.
      module NextActionResolver
        DONE_STATUSES = Owl::StepStatus::DONE_STATUSES
        # A `running` step blocks the same way a `blocked`/`failed` one does when
        # describing why no step is dispatchable, so `running` is layered on top
        # of the shared blocking set. Value is unchanged: %w[running blocked failed].
        BLOCKING_STEP_STATUSES = (%w[running] + Owl::StepStatus::BLOCKING_STATUSES).freeze

        # Stable action shape: every discriminated field is always present
        # (null when not applicable) so consumers can parse without probing.
        ACTION_FIELDS = {
          task_id: nil, step_id: nil, session_type: nil,
          skill: nil, variant: nil, blocker: nil, children: nil, reason: nil
        }.freeze

        module_function

        def call(root:, task_id: nil, now: Time.now)
          resolution = TaskResolver.resolve(root: root, task_id: task_id)
          return ok(no_available_task_action, resolution.merge(needs_adopt: false)) if resolution[:task_id].nil?

          ready_result = Owl::Workflows::Api.ready_steps(root: root, task_id: resolution[:task_id])
          return ready_result if ready_result.err?

          inspect_result = Owl::Tasks::Api.inspect(root: root, task_id: resolution[:task_id])
          return inspect_result if inspect_result.err?

          build(root: root, resolution: resolution, ready_value: ready_result.value,
                task_payload: inspect_result.value[:payload], now: now)
        end

        def build(root:, resolution:, ready_value:, task_payload:, now:)
          needs_adopt = needs_adopt?(
            task_payload: task_payload,
            claim: claim_entry(root: root, task_id: resolution[:task_id]),
            now: now
          )
          action = classify(
            root: root, resolution: resolution, ready_value: ready_value, task_payload: task_payload
          )
          ok(action, resolution.merge(needs_adopt: needs_adopt))
        end

        def classify(root:, resolution:, ready_value:, task_payload:)
          task_id = resolution[:task_id]
          ready = Array(ready_value[:ready])
          blocked = Array(ready_value[:blocked_by_children])
          awaiting_plan = Array(ready_value[:awaiting_plan_approval])
          conditional = Array(ready_value[:conditional_skip])

          if conditional.any?
            skip_conditional_action(task_id: task_id, entry: conditional.first)
          elsif ready.any?
            dispatch_action(root: root, task_id: task_id, step: ready.first,
                            workflow_key: ready_value[:workflow_key], task_payload: task_payload)
          elsif blocked.any?
            handoff_action(root: root, task_id: task_id)
          elsif awaiting_plan.any?
            await_plan_approval_action(task_id: task_id, step_id: awaiting_plan.first)
          elsif all_steps_done?(task_payload)
            action('done', task_id: task_id)
          else
            action('stop_blocked', task_id: task_id, blocker: describe_blocker(task_payload))
          end
        end

        def dispatch_action(root:, task_id:, step:, workflow_key:, task_payload:)
          step_id = step[:id].to_s
          definition_step = definition_step(root: root, workflow_key: workflow_key, step_id: step_id)
          action(
            'dispatch_step',
            task_id: task_id,
            step_id: step_id,
            session_type: step[:session_type],
            skill: definition_step ? definition_step['skill'] : nil,
            variant: resolve_variant(definition_step: definition_step, step_id: step_id, task_payload: task_payload)
          )
        end

        def handoff_action(root:, task_id:)
          aggregate = Owl::Tasks::Api.aggregate_status(root: root, task_id: task_id)
          action('handoff_composite', task_id: task_id, children: aggregate.ok? ? aggregate.value : nil)
        end

        # A `gate: plan_approved` step is ready except that the plan is not yet
        # approved. In a live session the orchestrator shows the plan and offers
        # a real choice (approve / request changes); headless this is a
        # stop-point awaiting an external `owl plan approve`.
        def await_plan_approval_action(task_id:, step_id:)
          action(
            'await_plan_approval',
            task_id: task_id,
            step_id: step_id,
            blocker: "step '#{step_id}' is held by the plan-approval gate; approve with " \
                     "'owl plan approve #{task_id}' or request changes via 'owl step reopen #{task_id} plan'"
          )
        end

        # A `when:`-conditional step whose predicate is false is held out of the
        # ready set and surfaced here. `owl next` stays read-only: it advises the
        # skip; the orchestrator performs `owl step skip TASK STEP --reason
        # condition_unmet` (which unblocks dependents) and loops. A pending
        # conditional skip is cleared before any dispatch so the real next step
        # is not chosen while a stale conditional step still gates its dependents.
        def skip_conditional_action(task_id:, entry:)
          step_id = (entry[:id] || entry['id']).to_s
          reason = (entry[:reason] || entry['reason'] || 'condition_unmet').to_s
          action(
            'skip_conditional_step',
            task_id: task_id,
            step_id: step_id,
            reason: reason,
            blocker: "step '#{step_id}' is held by a false `when:` predicate; auto-skip with " \
                     "'owl step skip #{task_id} #{step_id} --reason #{reason}'"
          )
        end

        def no_available_task_action
          action('no_available_task')
        end

        def definition_step(root:, workflow_key:, step_id:)
          definition = Owl::Workflows::Api.definition(root: root, workflow_key: workflow_key)
          return nil if definition.err?

          definition.value[:steps][step_id]
        end

        # Mirrors BundleBuilder#resolve_chosen_variant: the task's explicit
        # choice wins, else the step's declared default_variant; nil when the
        # step declares no variants or no choice resolves.
        def resolve_variant(definition_step:, step_id:, task_payload:)
          return nil unless definition_step.is_a?(Hash) && definition_step['variants'].is_a?(Hash)

          step_variants = task_payload['step_variants'].is_a?(Hash) ? task_payload['step_variants'] : {}
          chosen = step_variants[step_id] || step_variants[step_id.to_sym] || definition_step['default_variant']
          chosen.to_s.empty? ? nil : chosen.to_s
        end

        def all_steps_done?(task_payload)
          statuses = step_statuses(task_payload)
          !statuses.empty? && statuses.all? { |status| DONE_STATUSES.include?(status) }
        end

        def describe_blocker(task_payload)
          problem = Array(task_payload['steps']).find do |step|
            step.is_a?(Hash) && BLOCKING_STEP_STATUSES.include?(step['status'].to_s)
          end
          return "step '#{problem['id']}' is #{problem['status']}" if problem

          'no ready steps and the workflow terminal step is not complete'
        end

        # needs_adopt is true only when a step is stuck `running` AND the task
        # carries a lease that has expired — the "prior session died mid-step"
        # case the orchestrator must `adopt`. A running step with no lease is a
        # normal single-session in-flight step, not an adopt signal.
        def needs_adopt?(task_payload:, claim:, now:)
          return false unless running_step?(task_payload)
          return false if claim.nil?

          lease_expired?(claim, now)
        end

        def running_step?(task_payload)
          Array(task_payload['steps']).any? do |step|
            step.is_a?(Hash) && step['status'].to_s == 'running'
          end
        end

        def claim_entry(root:, task_id:)
          claims = Owl::Tasks::Api.claims(root: root)
          return nil if claims.err?

          Array(claims.value[:claims]).find { |entry| entry[:task_id].to_s == task_id.to_s }
        end

        def lease_expired?(claim, now)
          raw = claim[:expires_at]
          return true if raw.nil? || raw.to_s.empty?

          now >= Time.iso8601(raw.to_s)
        rescue ArgumentError
          true
        end

        def step_statuses(task_payload)
          Array(task_payload['steps']).filter_map do |step|
            step['status'].to_s if step.is_a?(Hash)
          end
        end

        def action(kind, fields = {})
          { kind: kind }.merge(ACTION_FIELDS).merge(fields)
        end

        def ok(action, resolution)
          Owl::Result.ok(
            ok: true,
            action: action,
            task_resolution: {
              source: resolution[:source],
              reason: resolution[:reason],
              needs_adopt: resolution.fetch(:needs_adopt, false)
            }
          )
        end
      end
    end
  end
end
