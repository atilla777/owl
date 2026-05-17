# frozen_string_literal: true

require_relative 'internal/skill_reader'

module Owl
  module Instructions
    module Api
      module_function

      def read_skill(root:, skill_id:)
        Internal::SkillReader.read(root: root, skill_id: skill_id)
      end
    end
  end
end
