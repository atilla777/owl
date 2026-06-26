# frozen_string_literal: true

require_relative '../../internal/registry_loader'
require_relative 'cache'

module Owl
  module Artifacts
    module Internal
      # Thin per-domain wrapper over Owl::Internal::RegistryLoader, supplying the
      # artifact registry path/namespace and the artifact per-entry field mapping.
      module RegistryLoader
        REGISTRY_PATH = '.owl/artifacts.yaml'

        module_function

        def load(root:)
          Owl::Internal::RegistryLoader.load(
            root: root,
            registry_path: REGISTRY_PATH,
            prefix: Cache::KEY_PREFIX,
            collection_key: 'artifacts',
            namespace: 'artifacts',
            label: 'Artifacts',
            normalize: method(:normalize)
          )
        end

        def normalize(key, body)
          {
            key: key.to_s,
            source: body['source'],
            # Provenance for upgrade-safety: seeded/Owl-shipped types default to
            # managed (read-only from the project side). Project-owned copies are
            # registered with `managed: false` and may be edited via the CLI.
            managed: body['managed'] != false
          }
        end
      end
    end
  end
end
