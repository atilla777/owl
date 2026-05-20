# frozen_string_literal: true

require_relative '../result'
require_relative '../internal/backend_resolver'
require_relative 'backend'
require_relative 'backends/filesystem'
require_relative 'local'

module Owl
  module Artifacts
    # Thin facade over artifact backends.
    #
    # All operations route through `Owl::Internal::BackendResolver` with
    # `scope: :artifacts`, so future non-filesystem backends can take over
    # artifact-type storage per project.
    #
    # `default_template` and `seeded_sources` run before any project exists
    # (`owl init` seed step) and therefore bypass `BackendResolver` and call
    # the default filesystem backend directly, mirroring the same pattern in
    # `Owl::Workflows::Api`.
    module Api
      # Keys that filesystem-backend payloads expose as transitional path
      # carriers. They are stripped from the public DTO so backends without a
      # local filesystem view can satisfy the same contract.
      STRIPPED_PATH_KEYS = %i[local source_path template_path path].freeze

      module_function

      def registry(root:)
        with_backend(root, &:registry)
      end

      def list(root:)
        with_backend(root, &:list)
      end

      def find(root:, key:)
        strip_local(with_backend(root) { |backend| backend.find(key: key) })
      end

      def resolve(root:, task_id:, artifact_key:)
        with_backend(root) { |backend| backend.resolve(task_id: task_id, artifact_key: artifact_key) }
      end

      def scaffold(root:, id:, body: nil, force: false)
        strip_local(with_backend(root) { |backend| backend.scaffold(id: id, body: body, force: force) })
      end

      def validate(root:, id_or_path:)
        strip_local(with_backend(root) { |backend| backend.validate(id_or_path: id_or_path) })
      end

      def local_paths(root:, key: nil)
        with_backend(root) do |backend|
          if backend.respond_to?(:local_paths_for)
            backend.local_paths_for(key: key)
          else
            Owl::Result.err(
              code: :no_local_view,
              message: "Backend '#{backend.class.name}' has no local filesystem view.",
              details: { backend: backend.class.name }
            )
          end
        end
      end

      def default_template
        default_filesystem_backend.default_template
      end

      def seeded_sources
        default_filesystem_backend.seeded_sources
      end

      def with_backend(root)
        backend_result = Owl::Internal::BackendResolver.resolve(root: root, scope: :artifacts)
        return backend_result if backend_result.err?

        yield backend_result.value
      end

      def default_filesystem_backend
        Backends::Filesystem.new(root: nil)
      end

      def strip_local(result)
        return result if result.err?
        return result unless result.value.is_a?(Hash)

        Owl::Result.ok(result.value.except(*STRIPPED_PATH_KEYS))
      end

      private_class_method :with_backend, :default_filesystem_backend, :strip_local
    end
  end
end
