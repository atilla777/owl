# frozen_string_literal: true

require_relative '../../internal/registry_loader'
require_relative 'cache'

module Owl
  module Workflows
    module Internal
      # Thin per-domain wrapper over Owl::Internal::RegistryLoader, supplying the
      # workflow registry path/namespace, the extra top-level `default_workflow`
      # field, and the workflow per-entry field mapping.
      module RegistryLoader
        REGISTRY_PATH = '.owl/workflows.yaml'

        module_function

        def load(root:)
          Owl::Internal::RegistryLoader.load(
            root: root,
            registry_path: REGISTRY_PATH,
            prefix: Cache::KEY_PREFIX,
            collection_key: 'workflows',
            namespace: 'workflows',
            label: 'Workflows',
            top_level: { default_workflow: 'default_workflow' },
            normalize: method(:normalize)
          )
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
