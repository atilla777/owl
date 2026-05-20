# frozen_string_literal: true

require 'pathname'
require 'yaml'

module Owl
  module Context
    module Internal
      module OverlayPaths
        module_function

        CONVENTIONS = [
          ['.owl', 'overlays'],
          ['docs', 'ai']
        ].freeze

        # Returns an ordered list of unique Pathname candidates for a step.
        # Convention paths come first (universal then variant-specific),
        # explicit config paths after.
        def collect(root:, step_id:, variant: nil)
          root_path = Pathname.new(root.to_s)
          variant_str = variant.to_s.strip
          variant_str = nil if variant_str.empty?

          (convention_paths(root: root_path, step_id: step_id) +
           variant_paths(root: root_path, step_id: step_id, variant: variant_str) +
           config_paths(root: root_path, step_id: step_id)).uniq
        end

        def convention_paths(root:, step_id:)
          CONVENTIONS.map { |parts| root.join(*parts, "#{step_id}.md") }
        end

        def variant_paths(root:, step_id:, variant:)
          return [] if variant.nil?

          CONVENTIONS.map { |parts| root.join(*parts, step_id.to_s, "#{variant}.md") }
        end

        def config_paths(root:, step_id:)
          config_file = root.join('.owl', 'config.yaml')
          return [] unless config_file.file?

          parsed = safe_load(config_file)
          entries = Array(parsed.dig('context_overlays', step_id))
          entries.filter_map { |rel| Pathname.new(rel.to_s) }.map do |rel|
            rel.absolute? ? rel : root.join(rel)
          end
        end

        def safe_load(path)
          YAML.safe_load(path.read, aliases: false) || {}
        rescue Psych::SyntaxError
          {}
        end

        private_class_method :convention_paths, :variant_paths, :config_paths, :safe_load
      end
    end
  end
end
