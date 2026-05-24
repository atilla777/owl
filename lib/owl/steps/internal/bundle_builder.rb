# frozen_string_literal: true

require_relative '../../result'
require_relative '../../artifacts/api'
require_relative '../../context/api'
require_relative '../../storage/api'
require_relative '../../subagents/internal/output_spec'
require_relative '../../tasks/api'
require_relative '../../tasks/internal/paths'
require_relative '../../workflows/api'
require_relative 'statuses'
require_relative 'step_projection'

module Owl
  module Steps
    module Internal
      module BundleBuilder
        module_function

        def call(root:, task_id:, step_id:)
          task_result = Owl::Tasks::Api.inspect(root: root, task_id: task_id)
          return task_result if task_result.err?

          payload = task_result.value[:payload]
          workflow_key = payload.dig('workflow', 'key')
          return task_workflow_missing(task_id) unless workflow_key

          step_variants = payload['step_variants'].is_a?(Hash) ? payload['step_variants'] : {}
          definition_result = Owl::Workflows::Api.definition(
            root: root,
            workflow_key: workflow_key,
            step_variants: step_variants
          )
          return definition_result if definition_result.err?

          definition = definition_result.value
          step = definition[:steps][step_id.to_s]
          return unknown_step_id(task_id, step_id) unless step

          template_result = extract_artifact_template(root: root, task_id: task_id, step: step)
          return template_result if template_result.is_a?(Owl::Result::Err)

          chosen_variant = resolve_chosen_variant(step: step, step_id: step_id, step_variants: step_variants)
          step_payload, context = split_step_payload(
            root: root, task_id: task_id, step: step, step_id: step_id, chosen_variant: chosen_variant
          )
          artifacts = extract_task_artifacts(root: root, task_id: task_id, definition: definition)
          overlays = extract_overlays(root: root, step_id: step_id, variant: chosen_variant)

          Result.ok(
            step: step_payload,
            context: context,
            overlays: overlays,
            artifact_template: template_result,
            execution_mode: execution_mode_for(definition: definition),
            step_report_schema: step_report_schema_for(step_payload),
            task: { id: task_id.to_s, title: payload['title'].to_s, artifacts: artifacts }
          )
        end

        def task_workflow_missing(task_id)
          Result.err(
            code: :task_workflow_missing,
            message: "Task '#{task_id}' has no workflow key in task.yaml.",
            details: { task_id: task_id.to_s }
          )
        end

        def unknown_step_id(task_id, step_id)
          Result.err(
            code: :unknown_step_id,
            message: "Step '#{step_id}' is not defined for task '#{task_id}'.",
            details: { task_id: task_id.to_s, step_id: step_id.to_s }
          )
        end

        # Subagent step report schema (RFC #1 §4.3, §5) for execution-typed steps.
        # Returns nil for discussion steps — they do not write a structured report.
        def step_report_schema_for(step_payload)
          return nil unless step_payload['session_type'] == 'execution'

          Owl::Subagents::Internal::OutputSpec.schema
        end

        def resolve_chosen_variant(step:, step_id:, step_variants:)
          return nil unless step['variants'].is_a?(Hash)

          chosen = step_variants[step_id.to_s] || step_variants[step_id.to_sym]
          (chosen || step['default_variant']).to_s.empty? ? nil : (chosen || step['default_variant']).to_s
        end

        def split_step_payload(root:, task_id:, step:, step_id:, chosen_variant: nil)
          context = step['context']
          step_payload = step.reject { |k| k == 'context' }
          status = current_step_status(root: root, task_id: task_id, step_id: step_id)
          step_payload['status'] = status || Statuses::DEFAULT.to_s
          step_payload['variant'] = chosen_variant if chosen_variant
          step_payload.merge!(StepProjection.project(step).transform_keys(&:to_s))
          [step_payload, context]
        end

        def current_step_status(root:, task_id:, step_id:)
          paths = Owl::Tasks::Internal::Paths.resolve(root: root)
          return nil if paths.err?

          Owl::Steps::Api.current_status(paths.value[:tasks], task_id, step_id)
        end

        def extract_artifact_template(root:, task_id:, step:)
          creates = Array(step['creates'])
          return nil if creates.empty?

          descriptor = Owl::Artifacts::Api.resolve(root: root, task_id: task_id, artifact_key: creates.first)
          return descriptor if descriptor.err?

          validation = descriptor.value[:validation] || {}
          {
            required_sections: validation['required_sections'] || validation[:required_sections] || [],
            frontmatter_schema: descriptor.value[:front_matter] || {}
          }
        end

        # Returns a hash { artifact_key => body_string } for every declared
        # artifact of the workflow whose file exists on disk. Missing artifacts
        # are omitted (not included as nil) — agents can detect absence by key.
        def extract_task_artifacts(root:, task_id:, definition:)
          artifacts = definition[:artifacts]
          return {} unless artifacts.is_a?(Hash) && !artifacts.empty?

          artifacts.each_with_object({}) do |(key, _decl), acc|
            body = read_artifact_body(root: root, task_id: task_id, artifact_key: key)
            acc[key.to_s] = body if body
          end
        end

        def read_artifact_body(root:, task_id:, artifact_key:)
          descriptor = Owl::Artifacts::Api.resolve(root: root, task_id: task_id, artifact_key: artifact_key)
          return nil if descriptor.err?

          path = descriptor.value[:path]
          return nil unless path && Owl::Storage::Api.exists?(path: path)

          read = Owl::Storage::Api.read(path: path)
          read.ok? ? read.value : nil
        end

        def extract_overlays(root:, step_id:, variant: nil)
          result = Owl::Context::Api.overlays_for(root: root, step_id: step_id, variant: variant)
          result.ok? ? result.value : []
        end

        def execution_mode_for(definition:)
          body = definition[:body]
          return nil unless body.is_a?(Hash)

          body['execution_mode'] || body[:execution_mode]
        end
      end
    end
  end
end
