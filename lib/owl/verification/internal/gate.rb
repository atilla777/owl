# frozen_string_literal: true

require_relative '../../result'
require_relative '../../tasks/api'
require_relative '../../workflows/api'
require_relative 'engine'

module Owl
  module Verification
    module Internal
      # Completion gate for steps flagged `verify: true`. Mirrors the
      # `publishes: true` step-marker precedent (`Publish::Internal::StepGate`):
      # a step opts into the objective verification gate via a boolean marker,
      # never a hardcoded id. The gate runs at `step complete` time, so the
      # result is fresh by construction.
      module Gate
        module_function

        # Returns:
        #   Result.ok(applicable: false)                       — step has no `verify: true`
        #   Result.ok(applicable: true, gate_active: false,
        #             warning: {...})                          — fail-open (no command)
        #   Result.ok(applicable: true, gate_active: true,
        #             status: 'passed'|'partial', warning:)    — passes the gate
        #   Result.err(code: :verification_failed, ...)        — blocks completion
        def call(root:, task_id:, step_id:, runner: CommandRunner)
          verify = verify_step?(root: root, task_id: task_id, step_id: step_id)
          return verify if verify.is_a?(Owl::Result::Err)
          return Result.ok(applicable: false) unless verify

          command = Engine.config_command(root: root)
          return inactive(task_id, step_id) if command.nil?

          run_result = Engine.run(root: root, task_id: task_id, command: command, runner: runner)
          return run_result if run_result.err?

          decide(run_result.value, task_id, step_id)
        end

        # First step flagged `verify: true`, by the publish-gate precedent. Used
        # by standalone tooling; nil when no step opts in.
        def resolve_step_id(workflow_body)
          steps = workflow_body.is_a?(Hash) ? (workflow_body['steps'] || workflow_body[:steps]) : nil
          return nil unless steps.is_a?(Array)

          marked = steps.find { |s| s.is_a?(Hash) && (s['verify'] || s[:verify]) == true }
          marked ? (marked['id'] || marked[:id]).to_s : nil
        end

        def verify_step?(root:, task_id:, step_id:)
          task = Owl::Tasks::Api.inspect(root: root, task_id: task_id)
          return task if task.err?

          workflow_key = task.value[:payload].dig('workflow', 'key')
          return Result.ok(false) unless workflow_key

          definition = Owl::Workflows::Api.definition(root: root, workflow_key: workflow_key)
          return definition if definition.err?

          step = definition.value[:steps][step_id.to_s] || {}
          (step['verify'] || step[:verify]) == true
        end

        def decide(value, task_id, step_id)
          case value[:status]
          when 'passed'
            Result.ok(applicable: true, gate_active: true, status: 'passed', verification: value)
          when 'partial'
            Result.ok(
              applicable: true, gate_active: true, status: 'partial', verification: value,
              warning: { code: :verification_partial, message: partial_message(value) }
            )
          else
            Result.err(
              code: :verification_failed,
              message: "Objective verification did not pass for step '#{step_id}' " \
                       "(status: #{value[:status]}, exit: #{value[:exit_code].inspect}).",
              details: {
                task_id: task_id.to_s, step_id: step_id.to_s,
                status: value[:status], exit_code: value[:exit_code], command: value[:command]
              }
            )
          end
        end

        def inactive(task_id, step_id)
          Result.ok(
            applicable: true, gate_active: false,
            warning: {
              code: :verification_gate_inactive,
              message: "Verification gate is inactive for step '#{step_id}' of task '#{task_id}': " \
                       "no #{Engine::COMMAND_KEY} configured. Completion proceeds without an objective run."
            }
          )
        end

        def partial_message(value)
          "Objective verification reported 'partial' (exit: #{value[:exit_code].inspect}); " \
            'completion proceeds with a warning.'
        end
      end
    end
  end
end
