# frozen_string_literal: true

require_relative '../../result'
require_relative '../../storage/api'

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
          skill_path = [root.to_s, SKILL_DIR, skill_id.to_s, SKILL_FILE].join('/')

          unless Owl::Storage::Api.exists?(path: skill_path)
            return Result.err(
              code: :skill_not_found,
              message: "Skill '#{skill_id}' not found at #{skill_path}",
              details: { skill_id: skill_id.to_s, path: skill_path }
            )
          end

          read_result = Owl::Storage::Api.read(path: skill_path)
          return read_result if read_result.err?

          contents = read_result.value
          command_path = [root.to_s, COMMAND_DIR, "#{skill_id}.md"].join('/')

          Result.ok(
            skill: {
              id: skill_id.to_s,
              path: skill_path,
              command_path: Owl::Storage::Api.exists?(path: command_path) ? command_path : nil
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
