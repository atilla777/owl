# frozen_string_literal: true

require_relative '../result'
require_relative '../internal/backend_resolver'
require_relative 'backend'
require_relative 'backends/filesystem'

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
      module_function

      def registry(root:)
        with_backend(root, &:registry)
      end

      def list(root:)
        with_backend(root, &:list)
      end

      def find(root:, key:)
        with_backend(root) { |backend| backend.find(key: key) }
      end

      def resolve(root:, task_id:, artifact_key:)
        with_backend(root) { |backend| backend.resolve(task_id: task_id, artifact_key: artifact_key) }
      end

      def scaffold(root:, id:, body: nil, force: false)
        with_backend(root) { |backend| backend.scaffold(id: id, body: body, force: force) }
      end

      def validate(root:, id_or_path:)
        with_backend(root) { |backend| backend.validate(id_or_path: id_or_path) }
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

      private_class_method :with_backend, :default_filesystem_backend
    end
  end
end
