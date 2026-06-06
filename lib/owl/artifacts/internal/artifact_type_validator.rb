# frozen_string_literal: true

require_relative '../../result'
require_relative '../../validation/internal/schema_check'

module Owl
  module Artifacts
    module Internal
      module ArtifactTypeValidator
        ALLOWED_FRONT_MATTER_TYPES = %w[object array string integer boolean null].freeze

        module_function

        def validate(body:, source_path: nil)
          errors = []
          unless body.is_a?(Hash)
            errors << error_at('/', 'Artifact type body must be a YAML mapping (object).')
            return Result.err(
              code: :artifact_type_validation_failed,
              message: 'Artifact type body is not a YAML mapping.',
              details: { errors: errors, source_path: source_path&.to_s }
            )
          end

          Owl::Validation::Internal::SchemaCheck.walk('artifact.json', body).each do |e|
            errors << error_at(e[:path], e[:message])
          end
          errors.concat(validate_top_level(body))
          errors.concat(validate_front_matter(body['front_matter']))
          errors.concat(validate_validation_block(body['validation']))

          if errors.empty?
            Result.ok(valid: true, errors: [], source_path: source_path&.to_s)
          else
            Result.err(
              code: :artifact_type_validation_failed,
              message: 'Artifact type definition failed validation.',
              details: { errors: errors, source_path: source_path&.to_s }
            )
          end
        end

        def validate_top_level(body)
          errors = []
          id = body['id']
          unless id.is_a?(String) && !id.strip.empty?
            errors << error_at('/id',
                               'Artifact type `id` is required and must be a non-empty string.')
          end

          title = body['title']
          unless title.is_a?(String) && !title.strip.empty?
            errors << error_at('/title',
                               'Artifact type `title` is required and must be a non-empty string.')
          end

          kind = body['kind']
          unless kind.is_a?(String) && !kind.strip.empty?
            errors << error_at('/kind',
                               'Artifact type `kind` is required and must be a non-empty string.')
          end

          description = body['description']
          if description && !description.is_a?(String)
            errors << error_at('/description',
                               'Artifact type `description` must be a string when present.')
          end

          default_template = body['default_template']
          if default_template && !default_template.is_a?(String)
            errors << error_at('/default_template',
                               'Artifact type `default_template` must be a string path when present.')
          end

          errors
        end

        def validate_front_matter(front_matter)
          return [] if front_matter.nil?
          unless front_matter.is_a?(Hash)
            return [error_at('/front_matter',
                             '`front_matter` must be a mapping when present.')]
          end

          errors = []
          type = front_matter['type']
          if type && !ALLOWED_FRONT_MATTER_TYPES.include?(type.to_s)
            errors << error_at('/front_matter/type',
                               "`front_matter.type` must be one of #{ALLOWED_FRONT_MATTER_TYPES.inspect} when present.")
          end

          required = front_matter['required']
          if required && !(required.is_a?(Array) && required.all?(String))
            errors << error_at('/front_matter/required',
                               '`front_matter.required` must be an array of strings when present.')
          end

          properties = front_matter['properties']
          if properties && !properties.is_a?(Hash)
            errors << error_at('/front_matter/properties', '`front_matter.properties` must be a mapping when present.')
          end

          errors
        end

        def validate_validation_block(validation)
          return [] if validation.nil?
          return [error_at('/validation', '`validation` must be a mapping when present.')] unless validation.is_a?(Hash)

          errors = []
          errors.concat(validate_required_string_array(validation['required_sections'], '/validation/required_sections',
                                                       'required_sections'))
          errors.concat(validate_required_string_array(validation['required_patterns'], '/validation/required_patterns',
                                                       'required_patterns'))
          errors.concat(validate_semantic_keys(validation))
          errors
        end

        SEMANTIC_BOOLEAN_KEYS = %w[forbid_empty_sections require_scenarios require_when_then].freeze

        def validate_semantic_keys(validation)
          errors = SEMANTIC_BOOLEAN_KEYS.flat_map do |key|
            validate_boolean(validation[key], "/validation/#{key}", key)
          end
          errors.concat(validate_placeholders(validation['forbid_placeholders']))
          errors
        end

        def validate_boolean(value, path, label)
          return [] if value.nil? || [true, false].include?(value)

          [error_at(path, "`validation.#{label}` must be a boolean when present.")]
        end

        def validate_placeholders(value)
          return [] if value.nil? || [true, false].include?(value)
          return [] if value.is_a?(Array) && value.all? { |s| s.is_a?(String) && !s.strip.empty? }

          [error_at('/validation/forbid_placeholders',
                    '`validation.forbid_placeholders` must be `true` or an array of non-empty strings when present.')]
        end

        def validate_required_string_array(value, path, label)
          return [] if value.nil?
          return [] if value.is_a?(Array) && value.all? { |s| s.is_a?(String) && !s.strip.empty? }

          [error_at(path, "`validation.#{label}` must be an array of non-empty strings when present.")]
        end

        def error_at(path, message)
          { path: path, message: message }
        end
      end
    end
  end
end
