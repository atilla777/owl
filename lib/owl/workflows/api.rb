# frozen_string_literal: true

require_relative '../result'
require_relative '../internal/backend_resolver'
require_relative 'backend'
require_relative 'backends/filesystem'
require_relative 'local'

module Owl
  module Workflows
    module Api
      # Keys that filesystem-backend payloads expose as transitional path
      # carriers. They are stripped from the public DTO so backends without a
      # local filesystem view can satisfy the same contract.
      STRIPPED_PATH_KEYS = %i[local source_path path template_path].freeze

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

      def scaffold(root:, id:, body: nil, kind: 'task', from: nil, force: false)
        strip_local(with_backend(root) do |backend|
          backend.scaffold(id: id, body: body, kind: kind, from: from, force: force)
        end)
      end

      def validate(root:, id_or_path:)
        strip_local(with_backend(root) { |backend| backend.validate(id_or_path: id_or_path) })
      end

      def graph(root:, workflow_key:)
        with_backend(root) { |backend| backend.graph(workflow_key: workflow_key) }
      end

      def definition(root:, workflow_key:, backend: nil, step_variants: {})
        with_backend(root) do |resolved_backend|
          resolved_backend.definition(
            workflow_key: workflow_key,
            backend: backend,
            step_variants: step_variants
          )
        end
      end

      def ready_steps(root:, task_id:)
        with_backend(root) { |backend| backend.ready_steps(task_id: task_id) }
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

      def seeded_sources
        default_filesystem_backend.seeded_sources
      end

      def default_template
        default_filesystem_backend.default_template
      end

      def with_backend(root)
        backend_result = Owl::Internal::BackendResolver.resolve(root: root, scope: :workflows)
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
