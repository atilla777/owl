# frozen_string_literal: true

require_relative '../../config/api'
require_relative '../../result'
require_relative '../../storage/api'

module Owl
  module Tasks
    module Internal
      module Paths
        REQUIRED_ROLES = %w[tasks index local_state].freeze

        module_function

        def resolve(root:)
          config_result = Owl::Config::Api.load(root: root)
          return config_result if config_result.err?

          profile = config_result.value.active_profile
          resolved = {}

          REQUIRED_ROLES.each do |role|
            path_result = Owl::Storage::Api.resolve(role: role, profile: profile, root: root)
            return path_result if path_result.err?

            resolved[role.to_sym] = path_result.value
          end

          Result.ok(resolved)
        end
      end
    end
  end
end
