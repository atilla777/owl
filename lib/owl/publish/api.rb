# frozen_string_literal: true

require_relative '../result'
require_relative '../tasks/api'
require_relative '../workflows/api'
require_relative 'internal/path_resolver'
require_relative 'internal/publisher'
require_relative 'internal/rules_loader'
require_relative 'internal/step_gate'

module Owl
  module Publish
    module Api
      module_function

      def run(root:, task_id:, dry_run: false, now: Time.now.utc)
        context = load_context(root: root, task_id: task_id)
        return context if context.is_a?(Owl::Result::Err)

        gate = Internal::StepGate.call(root: root, task_id: task_id, **context.slice(:task_payload, :workflow_body))
        return gate if gate.err?

        rules = load_rules(
          workflow_body: context[:workflow_body],
          workflow_key: context[:workflow_key],
          task_id: task_id
        )
        return rules if rules.is_a?(Owl::Result::Err)

        resolve = Internal::PathResolver.call(root: root, task_payload: context[:task_payload], rules: rules)
        return resolve if resolve.err?

        publish = Internal::Publisher.call(resolved_rules: resolve.value, dry_run: dry_run, now: now)
        return publish if publish.err?

        Result.ok(
          task_id: context[:task_payload]['id'].to_s,
          workflow_key: context[:workflow_key].to_s,
          dry_run: dry_run,
          step_status: gate.value[:status],
          results: publish.value
        )
      end

      def load_context(root:, task_id:)
        task_result = Owl::Tasks::Api.inspect(root: root, task_id: task_id)
        return task_result if task_result.err?

        task_payload = task_result.value[:payload]
        workflow_key = task_payload.dig('workflow', 'key')
        unless workflow_key
          return Result.err(
            code: :task_workflow_missing,
            message: "Task '#{task_id}' has no workflow key in task.yaml.",
            details: { task_id: task_id.to_s }
          )
        end

        workflow_result = Owl::Workflows::Api.find(root: root, key: workflow_key)
        return workflow_result if workflow_result.err?

        source = workflow_result.value[:source]
        unless source[:present]
          return Result.err(
            code: :workflow_source_missing,
            message: "Workflow source for '#{workflow_key}' is not present.",
            details: { key: workflow_key.to_s, source_path: source[:source_path] }
          )
        end

        { task_payload: task_payload,
          workflow_key: workflow_key,
          workflow_body: source[:body].is_a?(Hash) ? source[:body] : {} }
      end

      def load_rules(workflow_body:, workflow_key:, task_id:)
        rules_result = Internal::RulesLoader.call(workflow_body: workflow_body)
        return rules_result if rules_result.err?

        rules = rules_result.value
        return rules unless rules.empty?

        Result.err(
          code: :no_publishable_step,
          message: "Workflow '#{workflow_key}' has a 'publish' step but no 'publishes' rules.",
          details: { task_id: task_id.to_s, workflow_key: workflow_key.to_s }
        )
      end
    end
  end
end
