# frozen_string_literal: true

require_relative '../result'
require_relative '../internal/backend_resolver'
require_relative 'backend'
require_relative 'backends/filesystem'

module Owl
  module Config
    # Thin facade over config backends.
    #
    # All operations route through `Owl::Internal::BackendResolver` with
    # `scope: :config`, so future non-filesystem backends can take over config
    # storage per project.
    #
    # Layer-C bootstrap exception: `default_template(project_id:)` runs before
    # any project exists, so backend selection cannot depend on `.owl/config.yaml`
    # — it bypasses `BackendResolver` and calls the default filesystem backend
    # (`root: nil`). Same pattern as `Owl::Workflows::Api.default_template`.
    #
    # See also `Owl::Internal::BackendResolver.read_backend_name`, which itself
    # never routes through `Owl::Config::Api` (the underlying bootstrap cycle —
    # selecting the config backend depends on reading `.owl/config.yaml`).
    module Api
      # Read-only aliases: a convenience key resolves to a canonical storage
      # path on read, but cannot be written through (writes target the canonical
      # path explicitly). `version` exposes the stamped `owl.version` so users who
      # naturally try `owl config get version` get a value instead of null.
      READ_ALIASES = { 'version' => 'owl.version' }.freeze

      module_function

      def load(root:)
        with_backend(root, &:load)
      end

      def validate(root:)
        with_backend(root, &:validate)
      end

      def read_key(root:, key:)
        actual = READ_ALIASES.fetch(key, key)
        result = with_backend(root) { |backend| backend.read_key(key: actual) }
        return result if result.err? || actual == key

        # Resolve through the alias but report the key the caller requested.
        Result.ok(key: key, value: result.value[:value])
      end

      def write_key(root:, key:, value:)
        if READ_ALIASES.key?(key)
          canonical = READ_ALIASES.fetch(key)
          return Result.err(
            code: :config_key_aliased,
            message: "'#{key}' is a read-only alias of '#{canonical}'; set '#{canonical}' instead.",
            details: { key: key, canonical: canonical }
          )
        end

        with_backend(root) { |backend| backend.write_key(key: key, value: value) }
      end

      def snapshot(root:)
        with_backend(root, &:snapshot)
      end

      def default_template(project_id:)
        default_filesystem_backend.default_template(project_id: project_id)
      end

      def with_backend(root)
        backend_result = Owl::Internal::BackendResolver.resolve(root: root, scope: :config)
        return backend_result if backend_result.err?

        yield backend_result.value
      end

      def default_filesystem_backend
        Backends::Filesystem.new(root: nil)
      end

      private_class_method :with_backend, :default_filesystem_backend
    end
  end
end
