# frozen_string_literal: true

require 'pathname'
require 'yaml'

require_relative '../../result'
require_relative '../../storage/api'
require_relative '../backend'
require_relative '../internal/default_template'
require_relative '../internal/document'
require_relative '../internal/loader'
require_relative '../internal/path_accessor'
require_relative '../internal/serializer'
require_relative '../internal/validator'
require_relative '../internal/value_parser'

module Owl
  module Config
    module Backends
      # Filesystem implementation of `Owl::Config::Backend`.
      #
      # Reads `.owl/config.yaml` through `Owl::Storage::Api.read` (invariant
      # 5.11 — no domain-specific raw `File.read` outside of `Storage::Api`).
      #
      # Layer-C exception #2: `#write_key` uses `Internal::Serializer.write_atomic`
      # directly (atomic rename via `File.rename`) because `Storage::Api.write`
      # does not currently expose atomic-write semantics. When/if `Storage::Api`
      # grows `write_atomic`, this backend should migrate. Until then the atomic
      # rename lives here intentionally.
      class Filesystem
        include Owl::Config::Backend

        CONFIG_PATH = '.owl/config.yaml'

        def initialize(root:)
          @root = root
        end

        def load
          load_document
        end

        def validate
          load_result = load
          return load_result if load_result.err?

          document = load_result.value
          errors = Internal::Validator.validate(document)
          return Result.ok(document) if errors.empty?

          Result.err(
            code: :config_validation_failed,
            message: "Config validation failed with #{errors.length} error(s)",
            details: { errors: errors, document: document }
          )
        end

        def read_key(key:)
          load_result = load
          return load_result if load_result.err?

          value = Internal::PathAccessor.read(load_result.value.raw, key)
          Result.ok(key: key, value: value)
        rescue Internal::PathAccessor::InvalidPathError => e
          Result.err(code: :invalid_config_key, message: e.message, details: { key: key })
        rescue Internal::PathAccessor::MissingKeyError => e
          Result.err(code: :config_key_missing, message: e.message, details: { key: key })
        end

        def write_key(key:, value:)
          load_result = load
          return load_result if load_result.err?

          raw_copy = deep_dup(load_result.value.raw)

          begin
            parsed = Internal::ValueParser.parse(value)
          rescue Internal::ValueParser::InvalidJsonError => e
            return Result.err(code: :invalid_config_value, message: e.message, details: { key: key, raw_value: value })
          end

          begin
            Internal::PathAccessor.write(raw_copy, key, parsed)
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

          Internal::Serializer.write_atomic(root: @root, raw_hash: raw_copy)
          Result.ok(key: key, value: parsed)
        end

        def snapshot
          load_result = load
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

        # Layer-C exception #1 (see module header): default template renders
        # before any project exists, so `@root` is intentionally unused.
        def default_template(project_id:)
          Internal::DefaultTemplate.render(project_id: project_id)
        end

        private

        def load_document
          config_path = Pathname.new(@root.to_s) + CONFIG_PATH
          read_result = Owl::Storage::Api.read(path: config_path)

          if read_result.err?
            return Result.err(
              code: :config_missing,
              message: "Config file not found at #{config_path}",
              details: { path: config_path.to_s }
            )
          end

          raw = YAML.safe_load(read_result.value, aliases: false)
          unless raw.is_a?(Hash)
            return Result.err(
              code: :config_invalid,
              message: "Config file is not a YAML mapping: #{config_path}",
              details: { path: config_path.to_s }
            )
          end

          Result.ok(build_document(Internal::Loader.stringify_keys(raw)))
        rescue Psych::SyntaxError => e
          Result.err(code: :config_invalid_yaml, message: e.message, details: { path: config_path.to_s })
        end

        def build_document(raw_hash)
          Internal::Document.new(
            schema_version: raw_hash['schema_version'],
            project: raw_hash['project'] || {},
            owl_section: raw_hash['owl'] || {},
            workflow: raw_hash['workflow'] || {},
            storage: inject_role_defaults(raw_hash['storage'] || {}),
            settings_section: raw_hash['settings'] || {},
            raw: raw_hash
          )
        end

        # Backward compatibility: inject defaults for storage roles introduced
        # after the initial schema (e.g. `specs`) into every profile that omits
        # them, so legacy `.owl/config.yaml` files keep passing `STANDARD_ROLES`
        # validation and resolving the new role. Operates on a deep copy so the
        # on-disk config is never rewritten with the injected default.
        def inject_role_defaults(storage)
          storage = deep_dup(storage)
          profiles = storage['profiles']
          return storage unless profiles.is_a?(Hash)

          profiles.each_value do |profile|
            next unless profile.is_a?(Hash)

            roles = (profile['roles'] ||= {})
            next unless roles.is_a?(Hash)

            Owl::Storage::Api::ROLE_DEFAULTS.each do |role, path|
              roles[role] ||= { 'path' => path }
            end
          end
          storage
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
end
