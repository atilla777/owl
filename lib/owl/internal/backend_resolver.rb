# frozen_string_literal: true

require 'pathname'
require 'yaml'

require_relative '../result'
require_relative '../tasks/backends/filesystem'
require_relative '../workflows/backends/filesystem'

module Owl
  module Internal
    module BackendResolver
      module_function

      def resolve(root:, scope:)
        backend_name = read_backend_name(root: root)
        case backend_name
        when nil, 'filesystem'
          Owl::Result.ok(filesystem_backend(scope: scope, root: root))
        else
          Owl::Result.err(
            code: :unknown_backend,
            message: "Unknown Owl #{scope} backend: #{backend_name.inspect}",
            details: { scope: scope, backend_name: backend_name }
          )
        end
      end

      def filesystem_backend(scope:, root:)
        case scope
        when :tasks      then Owl::Tasks::Backends::Filesystem.new(root: root)
        when :workflows  then Owl::Workflows::Backends::Filesystem.new(root: root)
        else
          raise ArgumentError, "Unknown BackendResolver scope: #{scope.inspect}"
        end
      end

      def read_backend_name(root:)
        config_path = Pathname.new(root.to_s) + '.owl/config.yaml'
        return nil unless config_path.exist?

        raw = YAML.safe_load(config_path.read, aliases: false)
        return nil unless raw.is_a?(Hash)

        settings = raw['settings']
        return nil unless settings.is_a?(Hash)

        storage = settings['storage']
        return nil unless storage.is_a?(Hash)

        backend = storage['backend']
        backend.is_a?(String) && !backend.empty? ? backend : nil
      rescue Psych::SyntaxError
        nil
      end
    end
  end
end
