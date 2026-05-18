# frozen_string_literal: true

require 'pathname'

require_relative '../../result'
require_relative '../../artifacts/api'
require_relative '../../storage/api'
require_relative '../../tasks/api'
require_relative '../../tasks/internal/paths'
require_relative '../../workflows/api'
require_relative 'statuses'

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
          unless workflow_key
            return Result.err(
              code: :task_workflow_missing,
              message: "Task '#{task_id}' has no workflow key in task.yaml.",
              details: { task_id: task_id.to_s }
            )
          end

          definition_result = Owl::Workflows::Api.definition(root: root, workflow_key: workflow_key)
          return definition_result if definition_result.err?

          definition = definition_result.value
          step = definition[:steps][step_id.to_s]
          unless step
            return Result.err(
              code: :unknown_step_id,
              message: "Step '#{step_id}' is not defined for task '#{task_id}'.",
              details: { task_id: task_id.to_s, step_id: step_id.to_s }
            )
          end

          template_result = extract_artifact_template(root: root, task_id: task_id, step: step)
          return template_result if template_result.is_a?(Owl::Result::Err)

          step_payload, context = split_step_payload(root: root, task_id: task_id, step: step, step_id: step_id)
          spec_body = extract_spec_body(root: root, task_id: task_id, definition: definition)

          Result.ok(
            step: step_payload,
            context: context,
            artifact_template: template_result,
            task: { id: task_id.to_s, title: payload['title'].to_s, spec_body: spec_body }
          )
        end

        def split_step_payload(root:, task_id:, step:, step_id:)
          context = step['context']
          step_payload = step.reject { |k| k == 'context' }
          status = current_step_status(root: root, task_id: task_id, step_id: step_id)
          step_payload['status'] = status || Statuses::DEFAULT.to_s
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

        def extract_spec_body(root:, task_id:, definition:)
          artifacts = definition[:artifacts]
          return nil unless artifacts.is_a?(Hash) && artifacts.key?('spec')

          descriptor = Owl::Artifacts::Api.resolve(root: root, task_id: task_id, artifact_key: 'spec')
          return nil if descriptor.err?

          path = descriptor.value[:path]
          return nil unless path && File.exist?(path)

          read = Owl::Storage::Api.read(path: Pathname.new(path))
          read.ok? ? read.value : nil
        end
      end
    end
  end
end
