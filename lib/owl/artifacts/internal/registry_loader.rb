# frozen_string_literal: true

require 'pathname'
require 'yaml'

module Owl
  module Artifacts
    module Internal
      module RegistryLoader
        REGISTRY_PATH = '.owl/artifacts.yaml'

        module_function

        def load(root:)
          registry_path = Pathname.new(root.to_s) + REGISTRY_PATH

          unless registry_path.exist?
            return [:err, :artifacts_registry_missing,
                    "Artifacts registry not found at #{registry_path}",
                    { path: registry_path.to_s }]
          end

          raw = YAML.safe_load(registry_path.read, aliases: false)
          unless raw.is_a?(Hash)
            return [:err, :artifacts_registry_invalid,
                    "Artifacts registry is not a YAML mapping: #{registry_path}",
                    { path: registry_path.to_s }]
          end

          artifacts = raw['artifacts'] || {}
          entries = artifacts.map do |key, body|
            normalize(key, body || {})
          end

          [:ok, {
            schema_version: raw['schema_version'],
            entries: entries
          }]
        rescue Psych::SyntaxError => e
          [:err, :artifacts_registry_invalid_yaml, e.message, { path: registry_path.to_s }]
        end

        def normalize(key, body)
          {
            key: key.to_s,
            source: body['source']
          }
        end
      end
    end
  end
end
