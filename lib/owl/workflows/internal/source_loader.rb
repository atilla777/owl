# frozen_string_literal: true

require 'pathname'
require 'yaml'

module Owl
  module Workflows
    module Internal
      module SourceLoader
        CONTROL_DIR = '.owl'

        module_function

        def load(root:, source:)
          return { present: false } if source.nil? || source.empty?

          source_path = Pathname.new(root.to_s) + CONTROL_DIR + source

          return { present: false, source_path: source_path.to_s } unless source_path.exist?

          raw = YAML.safe_load(source_path.read, aliases: false)
          return { present: true, source_path: source_path.to_s, body: nil } unless raw.is_a?(Hash)

          {
            present: true,
            source_path: source_path.to_s,
            body: raw,
            description: raw['description'] || raw['title'],
            kind: raw['kind']
          }
        rescue Psych::SyntaxError => e
          { present: true, source_path: source_path.to_s, error: e.message }
        end
      end
    end
  end
end
