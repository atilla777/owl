# frozen_string_literal: true

require_relative '../../result'
require_relative '../../artifacts/internal/task_artifact_resolver'
require_relative '../../tasks/api'
require_relative 'artifact_hasher'
require_relative 'artifact_sha_collector'

module Owl
  module Steps
    module Internal
      module DriftDetector
        module_function

        def call(root:, task_id:, step_id:)
          recorded = recorded_shas(root: root, task_id: task_id, step_id: step_id)
          return [] if recorded.empty?

          recorded.flat_map { |artifact_key, sha| drift_event_for(root, task_id, step_id, artifact_key, sha) }.compact
        end

        def recorded_shas(root:, task_id:, step_id:)
          task = Owl::Tasks::Api.inspect(root: root, task_id: task_id)
          return {} if task.err?

          recorded = recorded_content_sha(task.value[:payload], step_id)
          return {} if recorded.nil?

          return normalize_single_sha(root, task_id, step_id, recorded) if recorded.is_a?(String)
          return recorded.transform_keys(&:to_s) if recorded.is_a?(Hash)

          {}
        end

        def recorded_content_sha(payload, step_id)
          steps = payload['steps'] || payload[:steps] || []
          step = steps.find { |s| s.is_a?(Hash) && (s['id'] || s[:id]).to_s == step_id.to_s }
          return nil unless step

          step['content_sha'] || step[:content_sha]
        end

        def normalize_single_sha(root, task_id, step_id, sha)
          creates = ArtifactShaCollector.creates_for(root: root, task_id: task_id, step_id: step_id)
          return {} if creates.is_a?(Owl::Result::Err) || creates.empty?

          { creates.first => sha }
        end

        def drift_event_for(root, task_id, step_id, artifact_key, recorded_sha)
          descriptor = Owl::Artifacts::Internal::TaskArtifactResolver.call(
            root: root, task_id: task_id, artifact_key: artifact_key
          )
          return nil if descriptor.err?
          return nil if descriptor.value[:multiple]

          unless descriptor.value[:exists]
            return {
              type: :missing, step_id: step_id.to_s, artifact_key: artifact_key.to_s, recorded_sha: recorded_sha
            }
          end

          actual = ArtifactHasher.call(path: descriptor.value[:path])
          return nil if actual.err?
          return nil if actual.value == recorded_sha

          {
            type: :modified,
            step_id: step_id.to_s,
            artifact_key: artifact_key.to_s,
            recorded_sha: recorded_sha,
            actual_sha: actual.value
          }
        end
      end
    end
  end
end
