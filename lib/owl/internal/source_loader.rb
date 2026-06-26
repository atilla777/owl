# frozen_string_literal: true

require 'pathname'
require 'yaml'

require_relative 'yaml_cache'

module Owl
  module Internal
    # Shared skeleton for the per-domain `<Domain>::Internal::SourceLoader`
    # wrappers: reads a `.owl/<source>` YAML file (cache-backed) and returns a
    # presence/body hash. Each domain supplies its own cache `prefix` and a
    # `fields` callable that maps the parsed hash to its domain-specific summary
    # keys (artifacts expose title/kind/description; workflows differ).
    module SourceLoader
      CONTROL_DIR = '.owl'

      module_function

      def load(root:, source:, prefix:, fields:)
        return { present: false } if source.nil? || source.empty?

        source_path = Pathname.new(root.to_s) + CONTROL_DIR + source
        return { present: false, source_path: source_path.to_s } unless source_path.exist?

        raw = YamlCache.fetch_yaml(source_path, prefix: prefix) do
          YAML.safe_load(source_path.read, aliases: false)
        end
        return { present: true, source_path: source_path.to_s, body: nil } unless raw.is_a?(Hash)

        { present: true, source_path: source_path.to_s, body: raw }.merge(fields.call(raw))
      rescue Psych::SyntaxError => e
        { present: true, source_path: source_path.to_s, error: e.message }
      end
    end
  end
end
