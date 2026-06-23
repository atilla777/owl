# frozen_string_literal: true

require_relative '../../result'
require_relative '../../tasks/api'
require_relative '../../workflows/api'
require_relative '../backend'
require_relative '../internal/docs_index'
require_relative '../internal/path_resolver'
require_relative '../internal/publisher'
require_relative '../internal/rules_loader'
require_relative '../internal/status_flipper'
require_relative '../internal/step_gate'

module Owl
  module Publish
    module Backends
      class Filesystem
        include Owl::Publish::Backend

        def initialize(root:)
          @root = root
        end

        def run(task_id:, dry_run: false, now: Time.now.utc)
          context = load_context(task_id: task_id)
          return context if context.is_a?(Owl::Result::Err)

          gate = Internal::StepGate.call(
            root: @root,
            task_id: task_id,
            **context.slice(:task_payload, :workflow_body)
          )
          return gate if gate.err?

          rules = load_rules(
            workflow_body: context[:workflow_body],
            workflow_key: context[:workflow_key],
            task_id: task_id
          )
          return rules if rules.is_a?(Owl::Result::Err)

          resolve = Internal::PathResolver.call(
            root: @root,
            task_payload: context[:task_payload],
            rules: rules
          )
          return resolve if resolve.err?

          published = publish_resolved(
            resolved_rules: resolve.value,
            workflow_body: context[:workflow_body],
            dry_run: dry_run,
            now: now
          )
          return published if published.is_a?(Owl::Result::Err)

          Result.ok(
            task_id: context[:task_payload]['id'].to_s,
            workflow_key: context[:workflow_key].to_s,
            dry_run: dry_run,
            step_status: gate.value[:status],
            **published
          )
        end

        private

        # Flip the design's status to `shipped` in the canonical source BEFORE
        # copying (so the copy carries `shipped`), then copy per rules, then
        # refresh the generated index. A flip failure returns here, never
        # copying a desynced source/published pair.
        def publish_resolved(resolved_rules:, workflow_body:, dry_run:, now:)
          flip = Internal::StatusFlipper.call(
            root: @root, workflow_body: workflow_body,
            resolved_rules: resolved_rules, dry_run: dry_run
          )
          return flip if flip.err?

          publish = Internal::Publisher.call(resolved_rules: resolved_rules, dry_run: dry_run, now: now)
          return publish if publish.err?

          index = Internal::DocsIndex.regenerate(root: @root, dry_run: dry_run)
          return index if index.err?

          { results: publish.value, design_status: flip.value[:design_status], index: index.value }
        end

        def load_context(task_id:)
          task_result = Owl::Tasks::Api.inspect(root: @root, task_id: task_id)
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

          workflow_result = Owl::Workflows::Api.find(root: @root, key: workflow_key)
          return workflow_result if workflow_result.err?

          source = workflow_result.value[:source]
          unless source[:present]
            return Result.err(
              code: :workflow_source_missing,
              message: "Workflow source for '#{workflow_key}' is not present.",
              details: { key: workflow_key.to_s }
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
            message: "Workflow '#{workflow_key}' has a publishing step but no 'publishes' rules.",
            details: { task_id: task_id.to_s, workflow_key: workflow_key.to_s }
          )
        end
      end
    end
  end
end
