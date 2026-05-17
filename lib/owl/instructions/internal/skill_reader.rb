# frozen_string_literal: true

require 'pathname'

require_relative '../../result'

module Owl
  module Instructions
    module Internal
      module SkillReader
        SKILL_DIR  = '.claude/skills'
        SKILL_FILE = 'SKILL.md'
        COMMAND_DIR = '.claude/commands'

        FRONTMATTER_RE = /\A---\s*\n.*?\n---\s*\n/m

        module_function

        def read(root:, skill_id:)
          root_path = Pathname.new(root.to_s)
          skill_path = root_path.join(SKILL_DIR, skill_id.to_s, SKILL_FILE)

          unless skill_path.exist?
            return Result.err(
              code: :skill_not_found,
              message: "Skill '#{skill_id}' not found at #{skill_path}",
              details: { skill_id: skill_id.to_s, path: skill_path.to_s }
            )
          end

          contents = skill_path.read
          command_path = root_path.join(COMMAND_DIR, "#{skill_id}.md")

          Result.ok(
            skill: {
              id: skill_id.to_s,
              path: skill_path.to_s,
              command_path: command_path.exist? ? command_path.to_s : nil
            },
            summary: extract_summary(contents)
          )
        end

        def extract_summary(contents)
          body = contents.sub(FRONTMATTER_RE, '')
          paragraphs = body.split(/\n{2,}/)
          paragraphs.each do |para|
            stripped = para.strip
            next if stripped.empty?
            next if stripped.start_with?('#')

            return stripped
          end
          ''
        end
      end
    end
  end
end
