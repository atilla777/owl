# frozen_string_literal: true

require 'yaml'

require_relative '../../result'

module Owl
  module Workflows
    module Internal
      # Splits an optional YAML frontmatter block off the head of a `.context.md`
      # body. Logic mirrors Owl::Subagents::Internal::OutputSpec#split_frontmatter
      # but is intentionally permissive about absence: a file without a leading
      # `---\n` returns `{ frontmatter: {}, body: text }` rather than an error,
      # because `.context.md` frontmatter is optional. Extracting a shared
      # `Owl::Frontmatter` reusable by OutputSpec is a deliberate follow-up.
      module FrontmatterParser
        module_function

        def parse(text)
          string = text.to_s
          return Result.ok(frontmatter: {}, body: string) unless string.start_with?("---\n")

          end_idx = string.index("\n---\n", 4)
          if end_idx.nil?
            return Result.err(
              code: :step_context_frontmatter_unterminated,
              message: 'YAML frontmatter block is not terminated by `---` on its own line.'
            )
          end

          yaml_segment = string[4..(end_idx - 1)]
          body_segment = string[(end_idx + 5)..] || ''

          frontmatter = safe_load_frontmatter(yaml_segment)
          return frontmatter if frontmatter.is_a?(Owl::Result::Err)

          unless frontmatter.is_a?(Hash)
            return Result.err(
              code: :step_context_frontmatter_invalid_root,
              message: 'Frontmatter must be a YAML mapping.'
            )
          end

          Result.ok(frontmatter: frontmatter, body: body_segment)
        end

        def safe_load_frontmatter(yaml_segment)
          YAML.safe_load(yaml_segment) || {}
        rescue Psych::SyntaxError => e
          Result.err(
            code: :step_context_frontmatter_parse_error,
            message: "Frontmatter YAML is invalid: #{e.message}"
          )
        end
      end
    end
  end
end
