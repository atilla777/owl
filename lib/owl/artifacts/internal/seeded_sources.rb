# frozen_string_literal: true

require_relative '../../internal/seeded_loader'

module Owl
  module Artifacts
    module Internal
      module SeededSources
        module_function

        SOURCE_DIR = 'artifacts'
        TARGET_PREFIX = '.owl/artifacts'

        def files
          Owl::Internal::SeededLoader.load(source_dir: SOURCE_DIR, target_prefix: TARGET_PREFIX)
        end

        def keys
          Owl::Internal::SeededLoader.subdirectories(source_dir: SOURCE_DIR)
        end
      end
    end
  end
end
