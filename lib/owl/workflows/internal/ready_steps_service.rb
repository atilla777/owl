# frozen_string_literal: true

require_relative '../../result'
require_relative 'condition_evaluator'
require_relative 'ready_resolver'
require_relative 'step_lookup'

module Owl
  module Workflows
    module Internal
      # Resolves the ready-step set for a task and applies the runtime gates that
      # the pure `ReadyResolver` cannot (it has no `root`): composite-children
      # completion, plan-approval, and per-step conditional `when:` predicates.
      # Returns the same `Result.ok` shape the backend exposes via `ready_steps`.
      module ReadyStepsService
        COMPOSITE_KIND = 'composite_task'
        GATE_CHILDREN_COMPLETE = 'children_complete'
        GATE_PLAN_APPROVED = 'plan_approved'
        CHILDREN_READY_AGGREGATES = %w[ready done].freeze
        CONDITION_UNMET_REASON = 'condition_unmet'

        module_function

        def call(root:, backend:, task_id:)
          require_relative '../../tasks/api'
          task_read = Owl::Tasks::Api.inspect(root: root, task_id: task_id)
          return task_read if task_read.err?

          payload = task_read.value[:payload]
          workflow_key = payload.dig('workflow', 'key')
          unless workflow_key
            return Result.err(
              code: :task_workflow_missing,
              message: "Task '#{task_id}' has no workflow key in task.yaml.",
              details: { task_id: task_id.to_s }
            )
          end

          graph_result = backend.graph(workflow_key: workflow_key)
          return graph_result if graph_result.err?

          definition_steps = definition_steps_for(backend: backend, workflow_key: workflow_key)

          ready = ReadyResolver.resolve(
            graph: graph_result.value,
            task_steps: payload['steps'] || [],
            definition_steps: definition_steps
          )

          blocked_by_children = []
          if payload['kind'].to_s == COMPOSITE_KIND
            ready, blocked_by_children = apply_children_gate(
              root: root, task_id: task_id, ready: ready, definition_steps: definition_steps
            )
          end

          ready, awaiting_plan_approval = apply_plan_approval_gate(
            root: root, task_id: task_id, payload: payload, ready: ready, definition_steps: definition_steps
          )

          ready, conditional_skip = apply_conditional_gate(
            root: root, task_id: task_id, ready: ready, definition_steps: definition_steps
          )

          Result.ok(
            task_id: task_id.to_s,
            workflow_key: workflow_key,
            ready: ready,
            blocked_by_children: blocked_by_children,
            awaiting_plan_approval: awaiting_plan_approval,
            conditional_skip: conditional_skip
          )
        end

        def definition_steps_for(backend:, workflow_key:)
          lookup = backend.find(key: workflow_key)
          return {} if lookup.err?

          source = lookup.value[:source]
          return {} unless source[:present]

          body = source[:body].is_a?(Hash) ? source[:body] : {}
          steps = body['steps'] || body[:steps] || []
          StepLookup.build(steps)
        end

        # First conditional-logic gate: for each otherwise-ready step that
        # declares a `when:` predicate, evaluate it against the named artifact's
        # body (ConditionEvaluator has `root`, keeping ReadyResolver pure). A
        # false predicate moves the step out of `ready` into `conditional_skip`
        # so the orchestrator auto-skips it (`condition_unmet`), unblocking its
        # dependents. An invalid/unreadable predicate fails open — the step
        # stays ready rather than silently dropping work; authoring-time
        # `workflow validate` is the guard against malformed predicates.
        # Returns [remaining_ready, conditional_skip_entries].
        def apply_conditional_gate(root:, task_id:, ready:, definition_steps:)
          conditional = []
          remaining = ready.reject do |entry|
            predicate = conditional_predicate(definition_steps[entry[:id].to_s])
            next false if predicate.nil?

            evaluation = ConditionEvaluator.evaluate(
              root: root, task_id: task_id, predicate: predicate
            )
            next false unless evaluation.ok? && evaluation.value[:met] == false

            conditional << { id: entry[:id].to_s, reason: CONDITION_UNMET_REASON }
            true
          end
          [remaining, conditional]
        end

        def conditional_predicate(definition)
          return nil unless definition.is_a?(Hash)

          predicate = definition['when']
          predicate.is_a?(Hash) ? predicate : nil
        end

        # Steps held out of the ready set — and surfaced under
        # `awaiting_plan_approval` — until the task's plan approval is recorded
        # and still matches the plan artifact's current content_sha. A step is
        # gated when EITHER the workflow definition flags it `gate: plan_approved`
        # OR the task opted into plan approval (`require_plan_approval: true`,
        # set at create time or via the `settings.plan_approval.required`
        # default) and the step consumes the `plan` artifact — the per-task
        # opt-in makes the checkpoint available on any plan-bearing workflow
        # (feature/hotfix/refactor) without shipping a duplicate workflow. Unlike
        # children_complete this applies to any task kind. Returns
        # [remaining_ready, awaiting_ids].
        def apply_plan_approval_gate(root:, task_id:, payload:, ready:, definition_steps:)
          opt_in = plan_approval_opt_in?(payload)
          gated_ids = ready.map { |entry| entry[:id].to_s }.select do |id|
            definition = definition_steps[id]
            next false unless definition.is_a?(Hash)

            definition['gate'].to_s == GATE_PLAN_APPROVED ||
              (opt_in && requires_plan_artifact?(definition))
          end
          return [ready, []] if gated_ids.empty?

          require_relative '../../tasks/internal/plan_approval'
          plan_sha = Owl::Tasks::Internal::PlanApproval.current_plan_sha(root: root, task_id: task_id)
          return [ready, []] if Owl::Tasks::Internal::PlanApproval.gate_open?(payload, plan_sha)

          remaining = ready.reject { |entry| gated_ids.include?(entry[:id].to_s) }
          [remaining, gated_ids]
        end

        def plan_approval_opt_in?(payload)
          payload.is_a?(Hash) && payload['require_plan_approval'] == true
        end

        def requires_plan_artifact?(definition)
          Array(definition['requires'] || definition[:requires]).map(&:to_s).include?('plan')
        end

        # For a composite parent, steps flagged `gate: children_complete` in the
        # workflow definition must not surface as ready until every child task is
        # ready/archived. The "wait for children" invariant lives here in the
        # readiness engine rather than only in orchestrator prose + the late
        # `owl archive` guard. Returns [remaining_ready, blocked_by_children_ids].
        def apply_children_gate(root:, task_id:, ready:, definition_steps:)
          gated_ids = ready.map { |entry| entry[:id].to_s }.select do |id|
            definition = definition_steps[id]
            definition.is_a?(Hash) && definition['gate'].to_s == GATE_CHILDREN_COMPLETE
          end
          return [ready, []] if gated_ids.empty?
          return [ready, []] if children_ready?(root: root, task_id: task_id)

          remaining = ready.reject { |entry| gated_ids.include?(entry[:id].to_s) }
          [remaining, gated_ids]
        end

        # Fails open (treats children as ready) when aggregate-status cannot be
        # computed — the `owl archive` runtime guard remains the backstop, so a
        # transient read error must not strand every other ready step.
        def children_ready?(root:, task_id:)
          require_relative '../../tasks/api'
          aggregate = Owl::Tasks::Api.aggregate_status(root: root, task_id: task_id)
          return true if aggregate.err?

          CHILDREN_READY_AGGREGATES.include?(aggregate.value[:aggregate].to_s)
        end
      end
    end
  end
end
