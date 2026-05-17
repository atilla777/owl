# frozen_string_literal: true

require_relative '../result'
require_relative 'internal/artifact_type_loader'
require_relative 'internal/default_template'
require_relative 'internal/registry_loader'
require_relative 'internal/source_loader'
require_relative 'internal/task_artifact_resolver'

module Owl
  module Artifacts
    module Api
      module_function

      def registry(root:)
        outcome = Internal::RegistryLoader.load(root: root)
        return Result.err(code: outcome[1], message: outcome[2], details: outcome[3] || {}) if outcome[0] == :err

        Result.ok(outcome[1])
      end

      def list(root:)
        registry_result = registry(root: root)
        return registry_result if registry_result.err?

        registry_data = registry_result.value
        artifacts = registry_data[:entries].map do |entry|
          source_info = Internal::SourceLoader.load(root: root, source: entry[:source])

          {
            key: entry[:key],
            title: source_info[:title],
            kind: source_info[:kind],
            description: source_info[:description],
            source: entry[:source],
            source_present: source_info[:present]
          }
        end

        Result.ok(artifacts)
      end

      def find(root:, key:)
        registry_result = registry(root: root)
        return registry_result if registry_result.err?

        entry = registry_result.value[:entries].find { |e| e[:key] == key.to_s }
        unless entry
          return Result.err(
            code: :unknown_artifact_type,
            message: "Artifact type '#{key}' is not declared in .owl/artifacts.yaml.",
            details: { key: key.to_s, available: registry_result.value[:entries].map { |e| e[:key] } }
          )
        end

        Internal::ArtifactTypeLoader.load(root: root, type_key: key, registry_entry: entry)
      end

      def resolve(root:, task_id:, artifact_key:)
        Internal::TaskArtifactResolver.call(root: root, task_id: task_id, artifact_key: artifact_key)
      end

      def default_template
        Internal::DefaultTemplate.render
      end
    end
  end
end
