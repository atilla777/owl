# frozen_string_literal: true

require_relative 'internal/seeded_sources'

module Owl
  module Skills
    module Api
      module_function

      def seeded_sources
        Internal::SeededSources.files
      end

      def step_skill_ids
        Internal::SeededSources.step_skill_ids
      end
    end
  end
end
