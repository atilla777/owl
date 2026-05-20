# frozen_string_literal: true

require_relative '../../result'
require_relative '../../tasks/api'
require_relative '../../workflows/api'
require_relative '../backend'
require_relative '../internal/artifact_runner'

module Owl
  module Validation
    module Backends
      class Filesystem
        include Owl::Validation::Backend

        def initialize(root:)
          @root = root
        end

        def artifact(task_id:, artifact_key:)
          Internal::ArtifactRunner.call(root: @root, task_id: task_id, artifact_key: artifact_key)
        end

        def task(task_id:)
          task_result = Owl::Tasks::Api.inspect(root: @root, task_id: task_id)
          return task_result if task_result.err?

          workflow_key = task_result.value[:payload].dig('workflow', 'key')
          unless workflow_key
            return Result.err(
              code: :task_workflow_missing,
              message: "Task '#{task_id}' has no workflow key in task.yaml.",
              details: { task_id: task_id.to_s }
            )
          end

          keys_result = workflow_artifact_keys(workflow_key: workflow_key)
          return keys_result if keys_result.err?

          results = keys_result.value.map do |key|
            outcome = Internal::ArtifactRunner.call(root: @root, task_id: task_id, artifact_key: key)
            if outcome.err?
              {
                artifact_key: key,
                valid: false,
                violations: [{
                  type: 'resolution_error',
                  level: 'error',
                  description: outcome.message,
                  code: outcome.code.to_s
                }],
                descriptor: nil
              }
            else
              outcome.value
            end
          end

          Result.ok(
            all_valid: results.all? { |r| r[:valid] },
            results: results
          )
        end

        private

        def workflow_artifact_keys(workflow_key:)
          lookup = Owl::Workflows::Api.find(root: @root, key: workflow_key)
          return lookup if lookup.err?

          source = lookup.value[:source]
          unless source[:present]
            return Result.err(
              code: :workflow_source_missing,
              message: "Workflow source for '#{workflow_key}' is not present.",
              details: { key: workflow_key.to_s }
            )
          end

          body = source[:body]
          artifacts = body.is_a?(Hash) ? (body['artifacts'] || {}) : {}
          keys = artifacts.is_a?(Hash) ? artifacts.keys.map(&:to_s) : []
          Result.ok(keys)
        end
      end
    end
  end
end
