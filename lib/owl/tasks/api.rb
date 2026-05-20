# frozen_string_literal: true

require_relative '../result'
require_relative '../internal/backend_resolver'
require_relative 'backend'
require_relative 'backends/filesystem'
require_relative 'local'

module Owl
  module Tasks
    module Api
      # Keys that filesystem-backend payloads expose as transitional path
      # carriers. They are stripped from the public DTO so backends without a
      # local filesystem view can satisfy the same contract; callers that need
      # paths use `Api.local_paths(...)` reflection instead.
      STRIPPED_PATH_KEYS = %i[local task_path index_path pointer_path path].freeze

      module_function

      def create(root:, workflow:, title:, parent_id: nil, kind: nil, step_variants: nil)
        strip_local(with_backend(root) do |backend|
          backend.create(
            workflow: workflow,
            title: title,
            parent_id: parent_id,
            kind: kind,
            step_variants: step_variants
          )
        end)
      end

      def set_step_variant(root:, task_id:, step_id:, variant:)
        with_backend(root) do |backend|
          backend.set_step_variant(
            task_id: task_id,
            step_id: step_id,
            variant: variant
          )
        end
      end

      def list(root:)
        strip_local(with_backend(root, &:list))
      end

      def inspect(root:, task_id:)
        strip_local(with_backend(root) { |backend| backend.inspect_task(task_id: task_id) })
      end

      def use(root:, task_id:)
        strip_local(with_backend(root) { |backend| backend.use(task_id: task_id) })
      end

      def current(root:)
        strip_local(with_backend(root, &:current))
      end

      def rebuild_index(root:)
        strip_local(with_backend(root, &:rebuild_index))
      end

      def children(root:, parent_id:)
        with_backend(root) { |backend| backend.children(parent_id: parent_id) }
      end

      def parent(root:, task_id:)
        with_backend(root) { |backend| backend.parent(task_id: task_id) }
      end

      def tree(root:)
        with_backend(root, &:tree)
      end

      def aggregate_status(root:, task_id:)
        with_backend(root) { |backend| backend.aggregate_status(task_id: task_id) }
      end

      def child_create(root:, parent_id:, workflow:, title:, brief_body: nil)
        strip_local(with_backend(root) do |backend|
          backend.child_create(
            parent_id: parent_id,
            workflow: workflow,
            title: title,
            brief_body: brief_body
          )
        end)
      end

      def archive(root:, task_id:, now: Time.now.utc)
        with_backend(root) { |backend| backend.archive_task(task_id: task_id, now: now) }
      end

      def local_paths(root:, task_id: nil)
        with_backend(root) do |backend|
          if backend.respond_to?(:local_paths_for)
            backend.local_paths_for(task_id: task_id)
          else
            Owl::Result.err(
              code: :no_local_view,
              message: "Backend '#{backend.class.name}' has no local filesystem view.",
              details: { backend: backend.class.name }
            )
          end
        end
      end

      def with_backend(root)
        backend_result = Owl::Internal::BackendResolver.resolve(root: root, scope: :tasks)
        return backend_result if backend_result.err?

        yield backend_result.value
      end

      def strip_local(result)
        return result if result.err?
        return result unless result.value.is_a?(Hash)

        Owl::Result.ok(result.value.except(*STRIPPED_PATH_KEYS))
      end
    end
  end
end
