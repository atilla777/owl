# frozen_string_literal: true

require_relative '../../storage/api'

module Owl
  module Config
    module Internal
      module Validator
        SUPPORTED_SCHEMA_VERSION = 1

        module_function

        def validate(document)
          errors = []

          unless document.schema_version == SUPPORTED_SCHEMA_VERSION
            errors << {
              code: :unsupported_schema_version,
              message: "Expected schema_version #{SUPPORTED_SCHEMA_VERSION}, got #{document.schema_version.inspect}"
            }
          end

          project_id = document.project['id']
          if project_id.nil? || project_id.to_s.strip.empty?
            errors << { code: :missing_project_id, message: 'project.id is required' }
          end

          storage = document.storage
          active_profile_name = storage['active_profile']
          if active_profile_name.nil? || active_profile_name.to_s.strip.empty?
            errors << { code: :missing_active_profile, message: 'storage.active_profile is required' }
          end

          profiles = storage['profiles'] || {}
          profile = profiles[active_profile_name.to_s] if active_profile_name

          if active_profile_name && profile.nil?
            errors << {
              code: :missing_profile,
              message: "Active profile '#{active_profile_name}' is not defined under storage.profiles",
              details: { available_profiles: profiles.keys }
            }
          elsif profile
            errors.concat(validate_profile(profile, active_profile_name))
          end

          errors.concat(validate_settings(document.settings_section))

          errors
        end

        SUPPORTED_STORAGE_BACKENDS = %w[filesystem].freeze
        SETTINGS_LANGUAGE_OPTIONAL_KEYS = %w[artifacts docs].freeze

        def validate_settings(settings)
          return [] if settings.nil? || (settings.is_a?(Hash) && settings.empty?)

          unless settings.is_a?(Hash)
            return [{
              code: :invalid_settings_shape,
              message: 'settings must be a mapping when present'
            }]
          end

          errors = []
          errors.concat(validate_settings_language(settings['language']))
          errors.concat(validate_settings_storage(settings['storage']))
          errors.concat(validate_settings_agent_targets(settings['agent_targets']))
          errors
        end

        SUPPORTED_AGENT_TARGETS = %w[claude opencode].freeze

        def validate_settings_agent_targets(agent_targets)
          return [] if agent_targets.nil?

          unless agent_targets.is_a?(Array) && !agent_targets.empty?
            return [{
              code: :invalid_settings_agent_targets_shape,
              message: 'settings.agent_targets must be a non-empty array when present'
            }]
          end

          unsupported = agent_targets.reject { |target| SUPPORTED_AGENT_TARGETS.include?(target) }
          return [] if unsupported.empty?

          [{
            code: :unsupported_settings_agent_target,
            message: "settings.agent_targets contains unsupported value(s): #{unsupported.join(', ')}; " \
                     "supported: #{SUPPORTED_AGENT_TARGETS.join(', ')}",
            details: { unsupported: unsupported, supported: SUPPORTED_AGENT_TARGETS }
          }]
        end

        def validate_settings_language(language)
          return [] if language.nil?

          unless language.is_a?(Hash)
            return [{
              code: :invalid_settings_language_shape,
              message: 'settings.language must be a mapping'
            }]
          end

          errors = []
          comm = language['communication']
          if comm.nil? || !comm.is_a?(String) || comm.strip.empty?
            errors << {
              code: :missing_settings_language_communication,
              message: 'settings.language.communication is required and must be a non-empty string'
            }
          end

          SETTINGS_LANGUAGE_OPTIONAL_KEYS.each do |key|
            value = language[key]
            next if value.nil?

            unless value.is_a?(String) && !value.strip.empty?
              errors << {
                code: :invalid_settings_language_value,
                message: "settings.language.#{key} must be a non-empty string when present",
                details: { key: key }
              }
            end
          end

          errors
        end

        def validate_settings_storage(storage)
          return [] if storage.nil?

          unless storage.is_a?(Hash)
            return [{
              code: :invalid_settings_storage_shape,
              message: 'settings.storage must be a mapping'
            }]
          end

          errors = []
          backend = storage['backend']
          if !backend.nil? && !SUPPORTED_STORAGE_BACKENDS.include?(backend)
            errors << {
              code: :unsupported_settings_storage_backend,
              message: "settings.storage.backend '#{backend}' is not supported; supported: #{SUPPORTED_STORAGE_BACKENDS.join(', ')}",
              details: { backend: backend, supported: SUPPORTED_STORAGE_BACKENDS }
            }
          end

          roles = storage['roles']
          if roles && !roles.is_a?(Hash)
            errors << {
              code: :invalid_settings_storage_roles_shape,
              message: 'settings.storage.roles must be a mapping'
            }
          elsif roles.is_a?(Hash)
            roles.each do |role_name, path|
              unless path.is_a?(String) && !path.strip.empty?
                errors << {
                  code: :invalid_settings_storage_role_path,
                  message: "settings.storage.roles.#{role_name} must be a non-empty string",
                  details: { role: role_name }
                }
              end
            end
          end

          errors
        end

        def validate_profile(profile, profile_name)
          errors = []
          roles = profile['roles'] || {}

          Storage::Api::STANDARD_ROLES.each do |role|
            entry = roles[role]
            if entry.nil?
              errors << {
                code: :missing_role,
                message: "Active profile '#{profile_name}' is missing required role '#{role}'",
                details: { role: role, profile: profile_name }
              }
              next
            end

            next if entry.is_a?(Hash) && entry['path'].is_a?(String) && !entry['path'].strip.empty?

            errors << {
              code: :invalid_role_definition,
              message: "Role '#{role}' in profile '#{profile_name}' must have a non-empty 'path' string",
              details: { role: role, profile: profile_name }
            }
          end

          errors
        end
      end
    end
  end
end
