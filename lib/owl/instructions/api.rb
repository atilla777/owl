# frozen_string_literal: true

require_relative 'internal/payload_builder'
require_relative 'internal/skill_reader'

module Owl
  module Instructions
    module Api
      module_function

      def read_skill(root:, skill_id:)
        Internal::SkillReader.read(root: root, skill_id: skill_id)
      end

      def build_payload(root:, task_id: nil, step_id: nil)
        Internal::PayloadBuilder.call(root: root, task_id: task_id, step_id: step_id)
      end
    end
  end
end
