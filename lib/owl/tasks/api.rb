# frozen_string_literal: true

require_relative '../result'
require_relative '../internal/backend_resolver'
require_relative 'backend'
require_relative 'backends/filesystem'
require_relative 'internal/plan_approval'
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

      def create(root:, workflow:, title:, parent_id: nil, kind: nil, step_variants: nil, priority: 0)
        strip_local(with_backend(root) do |backend|
          backend.create(
            workflow: workflow,
            title: title,
            parent_id: parent_id,
            kind: kind,
            step_variants: step_variants,
            priority: priority
          )
        end)
      end

      def set_priority(root:, task_id:, priority:)
        strip_local(with_backend(root) { |backend| backend.set_priority(task_id: task_id, priority: priority) })
      end

      def claim(root:, task_id: nil, next_: false, ttl: nil, label: nil, steal: false)
        strip_local(with_backend(root) do |backend|
          backend.claim(task_id: task_id, next_: next_, ttl: ttl, label: label, steal: steal)
        end)
      end

      def release(root:, task_id:, token:)
        strip_local(with_backend(root) { |backend| backend.release(task_id: task_id, token: token) })
      end

      def heartbeat(root:, task_id:, token:, ttl: nil)
        strip_local(with_backend(root) do |backend|
          backend.heartbeat(task_id: task_id, token: token, ttl: ttl)
        end)
      end

      def claims(root:)
        with_backend(root, &:claims)
      end

      def available(root:)
        with_backend(root, &:available)
      end

      def adopt(root:, task_id:, token: nil)
        strip_local(with_backend(root) { |backend| backend.adopt(task_id: task_id, token: token) })
      end

      # Record plan approval for a task, opening the optional `gate: plan_approved`
      # readiness gate. Lease-aware (rejected with :lease_held when a different
      # live session holds the claim) and idempotent for an already-approved
      # plan with the same content_sha.
      def approve_plan(root:, task_id:, token: nil)
        Internal::PlanApproval.approve(root: root, task_id: task_id, token: token)
      end

      # Read-only plan-approval status: { approved, plan_sha, gate_open }.
      def plan_status(root:, task_id:)
        Internal::PlanApproval.status(root: root, task_id: task_id)
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

      # Current-task pointer projected down to just its id. Shared primitive
      # for the orchestration selection ladder (Instructions / Status /
      # Orchestration) so each does not carry its own copy. Returns
      # Result.ok(task_id) or the underlying Err (e.g. no_current_task).
      def current_task_id(root:)
        result = current(root: root)
        return result if result.err?

        Owl::Result.ok(result.value[:task_id])
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

      def child_create(root:, parent_id:, workflow:, title:, brief_body: nil, validate_brief: false)
        strip_local(with_backend(root) do |backend|
          backend.child_create(
            parent_id: parent_id,
            workflow: workflow,
            title: title,
            brief_body: brief_body,
            validate_brief: validate_brief
          )
        end)
      end

      def archive(root:, task_id:, now: Time.now.utc)
        with_backend(root) { |backend| backend.archive_task(task_id: task_id, now: now) }
      end

      def abandon(root:, task_id:, reason: nil, now: Time.now.utc)
        strip_local(with_backend(root) do |backend|
          backend.abandon_task(task_id: task_id, reason: reason, now: now)
        end)
      end

      def delete(root:, task_id:)
        with_backend(root) { |backend| backend.delete_task(task_id: task_id) }
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

      private_class_method :with_backend, :strip_local
    end
  end
end
