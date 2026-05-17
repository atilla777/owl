# frozen_string_literal: true

require 'yaml'

module Owl
  module Validation
    module Internal
      module FrontMatterParser
        FENCE = "---\n"

        module_function

        def parse(body)
          source = body.to_s
          return { front_matter: nil, body: source, error: nil } unless source.start_with?(FENCE)

          rest = source[FENCE.length..]
          end_index = rest.index("\n---\n") || rest.index("\n---")
          return { front_matter: nil, body: source, error: :unterminated } unless end_index

          fm_text = rest[0...end_index]
          tail_offset = end_index + (rest[end_index, 5] == "\n---\n" ? 5 : 4)
          remaining = rest[tail_offset..] || ''

          begin
            parsed = YAML.safe_load(fm_text, permitted_classes: [Date, Time], aliases: false)
          rescue Psych::SyntaxError
            return { front_matter: nil, body: remaining, error: :invalid_yaml }
          end

          return { front_matter: nil, body: remaining, error: :not_a_mapping } unless parsed.is_a?(Hash)

          { front_matter: parsed, body: remaining, error: nil }
        end
      end
    end
  end
end
