# frozen_string_literal: true

require_relative '../../internal/source_loader'
require_relative 'cache'

module Owl
  module Workflows
    module Internal
      # Thin per-domain wrapper over Owl::Internal::SourceLoader, supplying the
      # workflow cache prefix and the workflow summary-field mapping (description
      # falls back to title; no standalone title field).
      module SourceLoader
        FIELDS = lambda do |raw|
          { description: raw['description'] || raw['title'], kind: raw['kind'] }
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
