# frozen_string_literal: true

require_relative '../result'
require_relative '../internal/backend_resolver'
require_relative 'backend'
require_relative 'backends/filesystem'

module Owl
  module Workflows
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

      def scaffold(root:, id:, body: nil, kind: 'task', from: nil, force: false)
        with_backend(root) do |backend|
          backend.scaffold(id: id, body: body, kind: kind, from: from, force: force)
        end
      end

      def validate(root:, id_or_path:)
        with_backend(root) { |backend| backend.validate(id_or_path: id_or_path) }
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

      private_class_method :with_backend, :default_filesystem_backend
    end
  end
end
