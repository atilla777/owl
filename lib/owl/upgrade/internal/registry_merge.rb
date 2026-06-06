# frozen_string_literal: true

module Owl
  module Upgrade
    module Internal
      # Line-merges a seeded registry (`.owl/workflows.yaml` / `.owl/artifacts.yaml`)
      # into the project's existing one: Owl-shipped (`managed: true`) entries are
      # refreshed/added from the seed, while project-owned entries (`managed:
      # false`) and user top-level keys (default_workflow, …) are preserved.
      module RegistryMerge
        module_function

        # entries_key: 'workflows' or 'artifacts'. Returns [merged_hash, changed?].
        def merge(existing:, seed:, entries_key:)
          existing = {} unless existing.is_a?(Hash)
          seed = {} unless seed.is_a?(Hash)

          merged = deep_dup(existing)
          merged['schema_version'] ||= seed['schema_version'] || 1
          merged['default_workflow'] ||= seed['default_workflow'] if seed.key?('default_workflow')

          out_entries = merged[entries_key].is_a?(Hash) ? merged[entries_key] : {}
          seed_entries = seed[entries_key].is_a?(Hash) ? seed[entries_key] : {}

          seed_entries.each do |key, seed_entry|
            existing_entry = out_entries[key]
            # Protect a project-owned entry that shadows a seeded key.
            next if existing_entry.is_a?(Hash) && existing_entry['managed'] == false

            out_entries[key] = seed_entry
          end

          merged[entries_key] = out_entries
          [merged, merged != existing]
        end

        def deep_dup(obj)
          case obj
          when Hash then obj.each_with_object({}) { |(k, v), acc| acc[k] = deep_dup(v) }
          when Array then obj.map { |v| deep_dup(v) }
          else obj
          end
        end
      end
    end
  end
end
