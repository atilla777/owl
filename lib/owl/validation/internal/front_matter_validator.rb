# frozen_string_literal: true

module Owl
  module Validation
    module Internal
      module FrontMatterValidator
        BOOLEAN_VALUES = [true, false].freeze
        TYPE_MATCHERS = {
          'object' => ->(v) { v.is_a?(Hash) },
          'array' => ->(v) { v.is_a?(Array) },
          'string' => ->(v) { v.is_a?(String) },
          'integer' => ->(v) { v.is_a?(Integer) },
          'boolean' => ->(v) { BOOLEAN_VALUES.include?(v) },
          'null' => :nil?.to_proc
        }.freeze

        module_function

        def validate(front_matter, schema)
          schema = {} unless schema.is_a?(Hash)
          violations = []
          fm = front_matter.is_a?(Hash) ? front_matter : {}

          Array(schema['required'] || schema[:required]).each do |key|
            violations << missing_key(key) unless fm.key?(key.to_s)
          end

          properties = schema['properties'] || schema[:properties] || {}
          properties = {} unless properties.is_a?(Hash)
          properties.each do |key, sub_schema|
            next unless fm.key?(key.to_s)

            violations.concat(validate_value(key.to_s, fm[key.to_s], sub_schema))
          end

          violations
        end

        def validate_value(key, value, sub_schema)
          sub_schema = {} unless sub_schema.is_a?(Hash)
          violations = []

          type = sub_schema['type'] || sub_schema[:type]
          if type
            matcher = TYPE_MATCHERS[type.to_s]
            violations << wrong_type(key, type, value) if matcher && !matcher.call(value)
          end

          enum = sub_schema['enum'] || sub_schema[:enum]
          violations << wrong_enum(key, enum, value) if enum.is_a?(Array) && !enum.include?(value)

          violations
        end

        def missing_key(key)
          {
            type: 'front_matter_invalid',
            field: key.to_s,
            level: 'error',
            description: "Required front matter key '#{key}' is missing."
          }
        end

        def wrong_type(key, expected_type, value)
          {
            type: 'front_matter_invalid',
            field: key,
            level: 'error',
            description: "Field '#{key}' must be of type '#{expected_type}' (got #{value.class})."
          }
        end

        def wrong_enum(key, enum_values, value)
          {
            type: 'front_matter_invalid',
            field: key,
            level: 'error',
            description: "Field '#{key}' is not one of [#{enum_values.join(', ')}] (got #{value.inspect})."
          }
        end
      end
    end
  end
end
