# frozen_string_literal: true

require_relative '../../result'

module Owl
  module Publish
    module Internal
      module RulesLoader
        REQUIRED_KEYS = %w[from to].freeze
        ALLOWED_KEYS = %w[from to optional].freeze

        module_function

        def call(workflow_body:)
          unless workflow_body.is_a?(Hash)
            return Result.err(
              code: :workflow_body_invalid,
              message: 'Workflow body is not a YAML mapping.'
            )
          end

          raw = workflow_body['publishes'] || workflow_body[:publishes]
          return Result.ok([]) if raw.nil?

          unless raw.is_a?(Array)
            return Result.err(
              code: :publishes_invalid,
              message: 'workflow.publishes must be an array of { from, to } rules.',
              details: { actual: raw.class.name }
            )
          end

          rules = []
          raw.each_with_index do |entry, index|
            parsed = parse_rule(entry, index)
            return parsed if parsed.is_a?(Owl::Result::Err)

            rules << parsed
          end

          Result.ok(rules)
        end

        def parse_rule(entry, index)
          unless entry.is_a?(Hash)
            return Result.err(
              code: :publishes_invalid,
              message: "publishes[#{index}] must be a mapping with keys 'from' and 'to'.",
              details: { index: index }
            )
          end

          normalized = entry.transform_keys(&:to_s)

          extras = normalized.keys - ALLOWED_KEYS
          unless extras.empty?
            return Result.err(
              code: :publishes_invalid,
              message: "publishes[#{index}] has unknown keys: #{extras.join(', ')}.",
              details: { index: index, unknown_keys: extras }
            )
          end

          REQUIRED_KEYS.each do |key|
            value = normalized[key]
            unless value.is_a?(String) && !value.strip.empty?
              return Result.err(
                code: :publishes_invalid,
                message: "publishes[#{index}].#{key} must be a non-empty string.",
                details: { index: index, key: key }
              )
            end
          end

          if normalized.key?('optional') && ![true, false].include?(normalized['optional'])
            return Result.err(
              code: :publishes_invalid,
              message: "publishes[#{index}].optional must be a boolean.",
              details: { index: index, key: 'optional' }
            )
          end

          {
            'from' => normalized.fetch('from'),
            'to' => normalized.fetch('to'),
            'optional' => normalized['optional'] == true
          }
        end
      end
    end
  end
end
