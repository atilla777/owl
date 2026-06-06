# frozen_string_literal: true

require_relative '../result'
require_relative '../internal/backend_resolver'
require_relative 'backend'
require_relative 'backends/filesystem'

module Owl
  module Storage
    # Thin facade over storage backends.
    #
    # `resolve(role:, profile:, root:, vars:)` routes through
    # `Owl::Internal::BackendResolver` with `scope: :storage`, so future
    # non-filesystem backends can take over role resolution per project.
    #
    # Layer-C bootstrap exceptions:
    #
    # * `detect_root(start:)` must run before any backend can be picked
    #   (backend selection itself depends on `.owl/config.yaml` inside the
    #   project root). It bypasses `BackendResolver` and calls the default
    #   filesystem backend, mirroring how `Owl::Workflows::Api` uses its
    #   default filesystem backend for `seeded_sources` / `default_template`.
    #
    # * `read` / `write` / `mkdir_p` / `exists?` accept absolute or
    #   project-relative paths without a `root:` keyword and therefore also
    #   route through the default filesystem backend in v1. When a remote or
    #   SQLite storage backend lands, these will be re-routed through
    #   `BackendResolver` and the facade signatures will gain `root:`.
    module Api
      STANDARD_ROLES = %w[control local_state index tasks archive docs].freeze

      module_function

      def detect_root(start:)
        default_filesystem_backend.detect_root(start: start)
      end

      def resolve(role:, profile:, root:, vars: {})
        with_backend(root) { |backend| backend.resolve(role: role, profile: profile, vars: vars) }
      end

      def write(path:, contents:)
        default_filesystem_backend.write(path: path, contents: contents)
      end

      def mkdir_p(path:)
        default_filesystem_backend.mkdir_p(path: path)
      end

      def read(path:)
        default_filesystem_backend.read(path: path)
      end

      def children(path:)
        default_filesystem_backend.children(path: path)
      end

      def exists?(path:)
        default_filesystem_backend.exists?(path: path)
      end

      def with_backend(root)
        backend_result = Owl::Internal::BackendResolver.resolve(root: root, scope: :storage)
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
