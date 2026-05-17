# frozen_string_literal: true

require_relative '../result'
require_relative 'internal/default_template'
require_relative 'internal/registry_loader'
require_relative 'internal/source_loader'

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

      def default_template
        Internal::DefaultTemplate.render
      end
    end
  end
end
