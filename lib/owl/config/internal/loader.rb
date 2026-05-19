# frozen_string_literal: true

require 'yaml'
require 'pathname'

require_relative 'document'

module Owl
  module Config
    module Internal
      module Loader
        CONFIG_PATH = '.owl/config.yaml'

        module_function

        def load(root:)
          config_path = Pathname.new(root.to_s) + CONFIG_PATH

          unless config_path.exist?
            return [:err, :config_missing, "Config file not found at #{config_path}", { path: config_path.to_s }]
          end

          raw = YAML.safe_load(config_path.read, aliases: false)
          unless raw.is_a?(Hash)
            return [:err, :config_invalid, "Config file is not a YAML mapping: #{config_path}",
                    { path: config_path.to_s }]
          end

          stringified = stringify_keys(raw)
          document = Document.new(
            schema_version: stringified['schema_version'],
            project: stringified['project'] || {},
            owl_section: stringified['owl'] || {},
            workflow: stringified['workflow'] || {},
            storage: stringified['storage'] || {},
            settings_section: stringified['settings'] || {},
            raw: stringified
          )
          [:ok, document]
        rescue Psych::SyntaxError => e
          [:err, :config_invalid_yaml, e.message, { path: config_path.to_s }]
        end

        def stringify_keys(value)
          case value
          when Hash
            value.each_with_object({}) { |(k, v), memo| memo[k.to_s] = stringify_keys(v) }
          when Array
            value.map { |v| stringify_keys(v) }
          else
            value
          end
        end
      end
    end
  end
end
