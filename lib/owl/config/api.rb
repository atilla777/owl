# frozen_string_literal: true

require_relative '../result'
require_relative 'internal/default_template'
require_relative 'internal/loader'
require_relative 'internal/path_accessor'
require_relative 'internal/serializer'
require_relative 'internal/validator'
require_relative 'internal/value_parser'

module Owl
  module Config
    module Api
      module_function

      def load(root:)
        outcome = Internal::Loader.load(root: root)

        if outcome[0] == :ok
          Result.ok(outcome[1])
        else
          Result.err(code: outcome[1], message: outcome[2], details: outcome[3] || {})
        end
      end

      def validate(root:)
        load_result = load(root: root)
        return load_result if load_result.err?

        document = load_result.value
        errors = Internal::Validator.validate(document)

        if errors.empty?
          Result.ok(document)
        else
          Result.err(
            code: :config_validation_failed,
            message: "Config validation failed with #{errors.length} error(s)",
            details: { errors: errors, document: document }
          )
        end
      end

      def default_template(project_id:)
        Internal::DefaultTemplate.render(project_id: project_id)
      end

      def read_key(root:, key:)
        load_result = load(root: root)
        return load_result if load_result.err?

        begin
          value = Internal::PathAccessor.read(load_result.value.raw, key)
          Result.ok(key: key, value: value)
        rescue Internal::PathAccessor::UnsupportedPathError => e
          Result.err(code: :unsupported_config_path, message: e.message, details: { key: key })
        rescue Internal::PathAccessor::InvalidPathError => e
          Result.err(code: :invalid_config_key, message: e.message, details: { key: key })
        rescue Internal::PathAccessor::MissingKeyError => e
          Result.err(code: :config_key_missing, message: e.message, details: { key: key })
        end
      end

      def write_key(root:, key:, value:)
        load_result = load(root: root)
        return load_result if load_result.err?

        raw_copy = deep_dup(load_result.value.raw)

        begin
          parsed = Internal::ValueParser.parse(value)
        rescue Internal::ValueParser::InvalidJsonError => e
          return Result.err(code: :invalid_config_value, message: e.message, details: { key: key, raw_value: value })
        end

        begin
          Internal::PathAccessor.write(raw_copy, key, parsed)
        rescue Internal::PathAccessor::UnsupportedPathError => e
          return Result.err(code: :unsupported_config_path, message: e.message, details: { key: key })
        rescue Internal::PathAccessor::InvalidPathError => e
          return Result.err(code: :invalid_config_key, message: e.message, details: { key: key })
        end

        candidate = build_document(raw_copy)
        errors = Internal::Validator.validate(candidate)

        unless errors.empty?
          return Result.err(
            code: :config_validation_failed,
            message: "Config would be invalid after setting #{key}: #{errors.length} error(s)",
            details: { errors: errors, key: key, value: parsed }
          )
        end

        Internal::Serializer.write_atomic(root: root, raw_hash: raw_copy)
        Result.ok(key: key, value: parsed)
      end

      def snapshot(root:)
        load_result = load(root: root)
        return load_result if load_result.err?

        document = load_result.value
        active_profile_name = document.storage['active_profile']
        profile = (document.storage['profiles'] || {})[active_profile_name.to_s] if active_profile_name
        roles_present = ((profile && profile['roles']) || {}).keys

        Result.ok(
          schema_version: document.schema_version,
          project: document.project,
          settings: document.settings_section,
          storage: {
            active_profile: active_profile_name,
            roles_present: roles_present
          }
        )
      end

      def build_document(raw_hash)
        Internal::Document.new(
          schema_version: raw_hash['schema_version'],
          project: raw_hash['project'] || {},
          owl_section: raw_hash['owl'] || {},
          workflow: raw_hash['workflow'] || {},
          storage: raw_hash['storage'] || {},
          settings_section: raw_hash['settings'] || {},
          raw: raw_hash
        )
      end

      def deep_dup(value)
        case value
        when Hash
          value.each_with_object({}) { |(k, v), memo| memo[k] = deep_dup(v) }
        when Array
          value.map { |v| deep_dup(v) }
        else
          value
        end
      end
    end
  end
end
