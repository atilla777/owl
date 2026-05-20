# frozen_string_literal: true

module Owl
  module Validation
    module Internal
      module JsonSchemaWalker
        TYPE_PREDICATES = {
          'object' => ->(v) { v.is_a?(Hash) },
          'array' => ->(v) { v.is_a?(Array) },
          'string' => ->(v) { v.is_a?(String) },
          'integer' => ->(v) { v.is_a?(Integer) },
          'number' => ->(v) { v.is_a?(Numeric) && !v.is_a?(TrueClass) && !v.is_a?(FalseClass) },
          'boolean' => ->(v) { v.is_a?(TrueClass) || v.is_a?(FalseClass) },
          'null' => lambda(&:nil?)
        }.freeze

        module_function

        def validate(schema, instance, path: '$')
          errors = []
          context = { root: schema }
          walk(schema, instance, path, errors, context)
          errors
        end

        def walk(schema, instance, path, errors, context)
          return unless schema.is_a?(Hash)

          schema = resolve_ref(schema, context) if schema.key?('$ref')
          return unless schema.is_a?(Hash)

          check_type(schema, instance, path, errors)
          check_enum(schema, instance, path, errors)
          check_const(schema, instance, path, errors)
          check_required(schema, instance, path, errors)
          check_properties(schema, instance, path, errors, context)
          check_additional_properties(schema, instance, path, errors, context)
          check_items(schema, instance, path, errors, context)
          check_min_length(schema, instance, path, errors)
          check_min_properties(schema, instance, path, errors)
          check_pattern(schema, instance, path, errors)
          check_not(schema, instance, path, errors, context)
        end

        def resolve_ref(schema, context)
          ref = schema['$ref']
          return schema unless ref.is_a?(String) && ref.start_with?('#/$defs/')

          name = ref.sub('#/$defs/', '')
          defs = context[:root].is_a?(Hash) ? context[:root]['$defs'] : nil
          defs.is_a?(Hash) ? defs[name] : nil
        end

        def check_type(schema, instance, path, errors)
          type = schema['type']
          return if type.nil?

          types = type.is_a?(Array) ? type : [type]
          ok = types.any? do |t|
            predicate = TYPE_PREDICATES[t.to_s]
            predicate&.call(instance)
          end
          return if ok

          errors << error(path, "expected type #{type.inspect}, got #{ruby_type_label(instance)}", keyword: 'type')
        end

        def check_enum(schema, instance, path, errors)
          enum = schema['enum']
          return unless enum.is_a?(Array)
          return if enum.include?(instance)

          errors << error(path, "value #{instance.inspect} is not one of #{enum.inspect}", keyword: 'enum')
        end

        def check_const(schema, instance, path, errors)
          return unless schema.key?('const')
          return if schema['const'] == instance

          errors << error(path, "value #{instance.inspect} does not equal const #{schema['const'].inspect}",
                          keyword: 'const')
        end

        def check_required(schema, instance, path, errors)
          required = schema['required']
          return unless required.is_a?(Array) && instance.is_a?(Hash)

          required.each do |key|
            next if instance.key?(key)

            errors << error(child_path(path, key), "missing required property `#{key}`", keyword: 'required')
          end
        end

        def check_properties(schema, instance, path, errors, context)
          properties = schema['properties']
          return unless properties.is_a?(Hash) && instance.is_a?(Hash)

          properties.each do |key, subschema|
            next unless instance.key?(key)

            walk(subschema, instance[key], child_path(path, key), errors, context)
          end
        end

        def check_additional_properties(schema, instance, path, errors, context)
          return unless instance.is_a?(Hash)

          additional = schema['additionalProperties']
          declared = schema['properties'].is_a?(Hash) ? schema['properties'].keys : []
          extras = instance.keys - declared

          case additional
          when false
            extras.each do |key|
              errors << error(child_path(path, key),
                              "additional property `#{key}` is not allowed",
                              keyword: 'additionalProperties')
            end
          when Hash
            extras.each do |key|
              walk(additional, instance[key], child_path(path, key), errors, context)
            end
          end
        end

        def check_items(schema, instance, path, errors, context)
          items = schema['items']
          return unless items.is_a?(Hash) && instance.is_a?(Array)

          instance.each_with_index do |element, idx|
            walk(items, element, "#{path}[#{idx}]", errors, context)
          end
        end

        def check_min_length(schema, instance, path, errors)
          min = schema['minLength']
          return unless min.is_a?(Integer) && instance.is_a?(String)
          return if instance.length >= min

          errors << error(path, "string length #{instance.length} is below minLength #{min}", keyword: 'minLength')
        end

        def check_min_properties(schema, instance, path, errors)
          min = schema['minProperties']
          return unless min.is_a?(Integer) && instance.is_a?(Hash)
          return if instance.size >= min

          errors << error(path, "object has #{instance.size} properties, below minProperties #{min}",
                          keyword: 'minProperties')
        end

        def check_pattern(schema, instance, path, errors)
          pattern = schema['pattern']
          return unless pattern.is_a?(String) && instance.is_a?(String)

          regex = Regexp.new(pattern)
          return if instance.match?(regex)

          errors << error(path, "string #{instance.inspect} does not match pattern /#{pattern}/", keyword: 'pattern')
        end

        def check_not(schema, instance, path, errors, context)
          subschema = schema['not']
          return unless subschema.is_a?(Hash)

          sub_errors = []
          walk(subschema, instance, path, sub_errors, context)
          return unless sub_errors.empty?

          required = subschema['required']
          message =
            if required.is_a?(Array)
              "must not have all of #{required.inspect} together"
            else
              'must not match negated schema'
            end
          errors << error(path, message, keyword: 'not')
        end

        def child_path(parent, key)
          if key.is_a?(Integer)
            "#{parent}[#{key}]"
          else
            "#{parent}.#{key}"
          end
        end

        def ruby_type_label(value)
          case value
          when Hash then 'object'
          when Array then 'array'
          when String then 'string'
          when Integer then 'integer'
          when Float then 'number'
          when TrueClass, FalseClass then 'boolean'
          when nil then 'null'
          else value.class.name
          end
        end

        def error(path, message, keyword:)
          { path: path, message: message, keyword: keyword }
        end
      end
    end
  end
end
