# frozen_string_literal: true

require_relative '../result'
require_relative 'internal/default_template'
require_relative 'internal/registry_loader'
require_relative 'internal/source_loader'

module Owl
  module Workflows
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
        workflows = registry_data[:entries].map do |entry|
          source_info = Internal::SourceLoader.load(root: root, source: entry[:source])

          {
            key: entry[:key],
            enabled: entry[:enabled],
            title: entry[:title],
            description: source_info[:description],
            kind: source_info[:kind],
            source: entry[:source],
            source_present: source_info[:present],
            aliases: entry[:aliases],
            priority: entry[:priority],
            version: entry[:version]
          }
        end

        Result.ok(workflows)
      end

      def default_template
        Internal::DefaultTemplate.render
      end
    end
  end
end
