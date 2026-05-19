# frozen_string_literal: true

require_relative '../../internal/seeded_loader'

module Owl
  module Skills
    module Internal
      module SeededSources
        module_function

        SKILLS_SOURCE_DIR = 'skills'
        SKILLS_TARGET_PREFIX = '.claude/skills'
        COMMANDS_SOURCE_DIR = 'commands'
        COMMANDS_TARGET_PREFIX = '.claude/commands'

        def files
          Owl::Internal::SeededLoader.load(source_dir: SKILLS_SOURCE_DIR, target_prefix: SKILLS_TARGET_PREFIX) +
            Owl::Internal::SeededLoader.load(source_dir: COMMANDS_SOURCE_DIR, target_prefix: COMMANDS_TARGET_PREFIX)
        end
      end
    end
  end
end
