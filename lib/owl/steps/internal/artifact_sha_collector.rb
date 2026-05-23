# frozen_string_literal: true

require_relative '../../result'
require_relative '../../artifacts/internal/task_artifact_resolver'
require_relative '../../tasks/api'
require_relative '../../workflows/api'
require_relative 'artifact_hasher'

module Owl
  module Steps
    module Internal
      module ArtifactShaCollector
        module_function

        def call(root:, task_id:, step_id:)
          creates = creates_for(root: root, task_id: task_id, step_id: step_id)
          return creates if creates.is_a?(Owl::Result::Err)
          return Result.ok(nil) if creates.empty?

          shas = {}
          creates.each do |key|
            descriptor = Owl::Artifacts::Internal::TaskArtifactResolver.call(
              root: root, task_id: task_id, artifact_key: key
            )
            return descriptor if descriptor.err?
            next if descriptor.value[:multiple]

            hash_result = ArtifactHasher.call(path: descriptor.value[:path])
            return hash_result if hash_result.err?

            shas[key.to_s] = hash_result.value
          end

          return Result.ok(nil) if shas.empty?
          return Result.ok(shas.values.first) if shas.size == 1

          Result.ok(shas)
        end

        def creates_for(root:, task_id:, step_id:)
          task = Owl::Tasks::Api.inspect(root: root, task_id: task_id)
          return task if task.err?

          workflow_key = task.value[:payload].dig('workflow', 'key')
          unless workflow_key
            return Result.err(
              code: :task_workflow_missing,
              message: "Task '#{task_id}' has no workflow key in task.yaml.",
              details: { task_id: task_id.to_s }
            )
          end

          definition = Owl::Workflows::Api.definition(root: root, workflow_key: workflow_key)
          return definition if definition.err?

          step = definition.value[:steps][step_id.to_s] || {}
          Array(step['creates'] || step[:creates]).map(&:to_s)
        end
      end
    end
  end
end
