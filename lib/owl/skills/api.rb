# frozen_string_literal: true

require_relative 'internal/seeded_sources'

module Owl
  module Skills
    module Api
      module_function

      def seeded_sources(targets: Internal::SeededSources::DEFAULT_TARGETS)
        Internal::SeededSources.files(targets: targets)
      end
    end
  end
end
