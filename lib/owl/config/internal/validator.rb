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
