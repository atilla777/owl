# frozen_string_literal: true

require_relative '../../internal/yaml_cache'

module Owl
  module Workflows
    module Internal
      # Thin per-domain wrapper over Owl::Internal::YamlCache, binding the
      # workflow cache-key namespace.
      module Cache
        KEY_PREFIX = 'workflow'

        module_function

        def fetch_yaml(path, &)
          Owl::Internal::YamlCache.fetch_yaml(path, prefix: KEY_PREFIX, &)
        end
      end
    end
  end
end
