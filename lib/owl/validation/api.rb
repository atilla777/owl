# frozen_string_literal: true

require_relative '../result'
require_relative '../internal/backend_resolver'
require_relative 'backend'
require_relative 'backends/filesystem'

module Owl
  module Validation
    # Thin facade over validation backends.
    #
    # `artifact` and `task` route through `Owl::Internal::BackendResolver` with
    # `scope: :validation`, so future non-filesystem backends can take over
    # validation per project. The filesystem backend reads artifact bodies via
    # `Owl::Storage::Api` and bundled JSON schemas via `Owl::Internal::GemAssets`.
    module Api
      module_function

      def artifact(root:, task_id:, artifact_key:)
        with_backend(root) { |backend| backend.artifact(task_id: task_id, artifact_key: artifact_key) }
      end

      def task(root:, task_id:)
        with_backend(root) { |backend| backend.task(task_id: task_id) }
      end

      def with_backend(root)
        backend_result = Owl::Internal::BackendResolver.resolve(root: root, scope: :validation)
        return backend_result if backend_result.err?

        yield backend_result.value
      end

      private_class_method :with_backend
    end
  end
end
