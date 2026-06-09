# frozen_string_literal: true

require_relative '../result'
require_relative '../internal/backend_resolver'
require_relative 'backend'
require_relative 'backends/filesystem'

module Owl
  module Locks
    # Thin facade over repo-scoped advisory locks.
    #
    # A lock serializes a cross-session operation (v1: pushing to `main` from
    # the `commit_push` step) by atomically creating a single TTL'd file under
    # the `local_state` storage role. Like the tasks claim lease it reuses
    # `Owl::Result` (no per-domain `result.rb`) and routes through
    # `Owl::Internal::BackendResolver` with `scope: :locks`.
    module Api
      module_function

      def acquire(root:, name:, ttl: nil, token: nil, steal: false)
        with_backend(root) { |backend| backend.acquire(name: name, ttl: ttl, token: token, steal: steal) }
      end

      def release(root:, name:, token:)
        with_backend(root) { |backend| backend.release(name: name, token: token) }
      end

      def with_backend(root)
        backend_result = Owl::Internal::BackendResolver.resolve(root: root, scope: :locks)
        return backend_result if backend_result.err?

        yield backend_result.value
      end

      private_class_method :with_backend
    end
  end
end
