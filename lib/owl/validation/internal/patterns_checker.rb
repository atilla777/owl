# frozen_string_literal: true

module Owl
  module Validation
    module Internal
      module PatternsChecker
        DEFAULT_LEVEL = 'error'
        DEFAULT_TYPE = 'regex'

        module_function

        def check(body, required_patterns)
          patterns = Array(required_patterns)
          return [] if patterns.empty?

          text = body.to_s
          patterns.flat_map { |spec| check_pattern(text, spec) }.compact
        end

        def check_pattern(text, spec)
          spec = { 'pattern' => spec.to_s } unless spec.is_a?(Hash)
          pattern = spec['pattern'] || spec[:pattern]
          return [] if pattern.nil? || pattern.to_s.empty?

          pattern_type = (spec['type'] || spec[:type] || DEFAULT_TYPE).to_s
          level = (spec['level'] || spec[:level] || DEFAULT_LEVEL).to_s
          description = spec['description'] || spec[:description] ||
                        "Required pattern '#{pattern}' not found."

          return [] if match?(text, pattern, pattern_type)

          [{
            type: 'missing_pattern',
            pattern: pattern.to_s,
            pattern_type: pattern_type,
            level: level,
            description: description.to_s
          }]
        end

        def match?(text, pattern, pattern_type)
          case pattern_type
          when 'substring'
            text.include?(pattern.to_s)
          else
            text.match?(Regexp.new(pattern.to_s))
          end
        end
      end
    end
  end
end
