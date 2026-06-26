# frozen_string_literal: true

require_relative '../../internal/source_loader'
require_relative 'cache'

module Owl
  module Artifacts
    module Internal
      # Thin per-domain wrapper over Owl::Internal::SourceLoader, supplying the
      # artifact cache prefix and the artifact summary-field mapping.
      module SourceLoader
        FIELDS = lambda do |raw|
          { title: raw['title'], kind: raw['kind'], description: raw['description'] }
        end

        module_function

        def load(root:, source:)
          Owl::Internal::SourceLoader.load(
            root: root, source: source, prefix: Cache::KEY_PREFIX, fields: FIELDS
          )
        end
      end
    end
  end
end
