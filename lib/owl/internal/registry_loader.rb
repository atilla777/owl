# frozen_string_literal: true

require 'pathname'
require 'yaml'

require_relative 'yaml_cache'

module Owl
  module Internal
    # Shared skeleton for the per-domain `<Domain>::Internal::RegistryLoader`
    # wrappers (artifacts/workflows). The on-disk shape is identical (a YAML
    # mapping with `schema_version` and a collection of named entries); each
    # domain differs only in: the registry path, cache prefix, the collection
    # key, the error symbol/label namespace, any extra top-level fields to
    # surface, and the per-entry `normalize` callable (the distinct field
    # mappings stay domain-local — passed in here, never flattened together).
    module RegistryLoader
      module_function

      def load(root:, registry_path:, prefix:, collection_key:, namespace:, label:, normalize:, top_level: {})
        path = Pathname.new(root.to_s) + registry_path

        unless path.exist?
          return [:err, :"#{namespace}_registry_missing",
                  "#{label} registry not found at #{path}",
                  { path: path.to_s }]
        end

        raw = YamlCache.fetch_yaml(path, prefix: prefix) do
          YAML.safe_load(path.read, aliases: false)
        end
        unless raw.is_a?(Hash)
          return [:err, :"#{namespace}_registry_invalid",
                  "#{label} registry is not a YAML mapping: #{path}",
                  { path: path.to_s }]
        end

        entries = (raw[collection_key] || {}).map { |key, body| normalize.call(key, body || {}) }

        result = { schema_version: raw['schema_version'] }
        top_level.each { |out_key, raw_key| result[out_key] = raw[raw_key] }
        result[:entries] = entries

        [:ok, result]
      rescue Psych::SyntaxError => e
        [:err, :"#{namespace}_registry_invalid_yaml", e.message, { path: path.to_s }]
      end
    end
  end
end
