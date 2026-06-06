# frozen_string_literal: true

require 'pathname'
require 'yaml'

require_relative 'cache'

module Owl
  module Workflows
    module Internal
      module RegistryLoader
        REGISTRY_PATH = '.owl/workflows.yaml'

        module_function

        def load(root:)
          registry_path = Pathname.new(root.to_s) + REGISTRY_PATH

          unless registry_path.exist?
            return [:err, :workflows_registry_missing,
                    "Workflows registry not found at #{registry_path}",
                    { path: registry_path.to_s }]
          end

          raw = Cache.fetch_yaml(registry_path) do
            YAML.safe_load(registry_path.read, aliases: false)
          end
          unless raw.is_a?(Hash)
            return [:err, :workflows_registry_invalid,
                    "Workflows registry is not a YAML mapping: #{registry_path}",
                    { path: registry_path.to_s }]
          end

          workflows = raw['workflows'] || {}
          entries = workflows.map do |key, body|
            normalize(key, body || {})
          end

          [:ok, {
            schema_version: raw['schema_version'],
            default_workflow: raw['default_workflow'],
            entries: entries
          }]
        rescue Psych::SyntaxError => e
          [:err, :workflows_registry_invalid_yaml, e.message, { path: registry_path.to_s }]
        end

        def normalize(key, body)
          {
            key: key.to_s,
            enabled: body['enabled'] != false,
            version: body['version'],
            source: body['source'],
            title: body['title'],
            aliases: Array(body['aliases']),
            priority: body['priority'],
            # Provenance for upgrade-safety: seeded/Owl-shipped workflows default
            # to managed (read-only); project-owned clones register managed: false.
            managed: body['managed'] != false
          }
        end
      end
    end
  end
end
