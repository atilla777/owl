# frozen_string_literal: true

require 'pathname'
require 'yaml'

require_relative '../../result'

module Owl
  module Tasks
    module Internal
      module IndexReader
        module_function

        def read(index_path:)
          path = Pathname.new(index_path.to_s)
          return Result.ok(schema_version: 1, tasks: []) unless path.exist?

          raw = YAML.safe_load(path.read, aliases: false, permitted_classes: [Time])
          unless raw.is_a?(Hash)
            return Result.err(
              code: :index_yaml_invalid,
              message: "tasks/index.yaml is not a YAML mapping: #{path}",
              details: { path: path.to_s }
            )
          end

          tasks = raw['tasks']
          tasks = [] unless tasks.is_a?(Array)

          Result.ok(schema_version: raw['schema_version'], tasks: tasks)
        rescue Psych::SyntaxError => e
          Result.err(code: :index_yaml_invalid, message: e.message, details: { path: path.to_s })
        end
      end
    end
  end
end
