# frozen_string_literal: true

require_relative '../result'
require_relative '../internal/backend_resolver'
require_relative 'backend'
require_relative 'backends/filesystem'

module Owl
  module Publish
    # Thin facade over publish backends.
    #
    # All operations route through `Owl::Internal::BackendResolver` with
    # `scope: :publish`, so future non-filesystem backends can take over how
    # task artifacts are copied to their target storage role per project.
    module Api
      module_function

      def run(root:, task_id:, dry_run: false, now: Time.now.utc)
        with_backend(root) { |backend| backend.run(task_id: task_id, dry_run: dry_run, now: now) }
      end

      def with_backend(root)
        backend_result = Owl::Internal::BackendResolver.resolve(root: root, scope: :publish)
        return backend_result if backend_result.err?

        yield backend_result.value
      end

      private_class_method :with_backend
    end
  end
end
