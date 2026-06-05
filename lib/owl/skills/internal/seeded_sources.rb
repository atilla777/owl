# frozen_string_literal: true

require_relative '../../internal/seeded_loader'

module Owl
  module Skills
    module Internal
      module SeededSources
        module_function

        SKILLS_SOURCE_DIR = 'skills'
        COMMANDS_SOURCE_DIR = 'commands'

        # Agent harnesses discover materialized skills/commands under different
        # folders. `claude` is Claude Code's layout; `opencode` is OpenCode's
        # native layout (used when OpenCode's `.claude/` compatibility is off).
        TARGET_PREFIXES = {
          claude: { skills: '.claude/skills', commands: '.claude/commands' },
          opencode: { skills: '.opencode/skills', commands: '.opencode/commands' }
        }.freeze

        DEFAULT_TARGETS = %i[claude].freeze

        def files(targets: DEFAULT_TARGETS)
          targets.flat_map do |target|
            prefixes = TARGET_PREFIXES.fetch(target)
            Owl::Internal::SeededLoader.load(source_dir: SKILLS_SOURCE_DIR, target_prefix: prefixes[:skills]) +
              Owl::Internal::SeededLoader.load(source_dir: COMMANDS_SOURCE_DIR, target_prefix: prefixes[:commands])
          end
        end
      end
    end
  end
end
