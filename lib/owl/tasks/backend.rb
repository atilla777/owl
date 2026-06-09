# frozen_string_literal: true

module Owl
  module Tasks
    class UnknownBackendError < StandardError; end

    # Public contract for an Owl tasks backend.
    #
    # Filesystem is the v1 implementation (see Backends::Filesystem). Future backends
    # (e.g. Obsidian, SQLite) implement the same instance methods. A backend is
    # constructed for a specific repository root and exposes task operations without
    # repeating the root in every call.
    module Backend
      def list
        raise NotImplementedError
      end

      def inspect_task(task_id:)
        raise NotImplementedError
      end

      def create(workflow:, title:, parent_id: nil, kind: nil, step_variants: nil, priority: 0)
        raise NotImplementedError
      end

      def set_step_variant(task_id:, step_id:, variant:)
        raise NotImplementedError
      end

      def set_priority(task_id:, priority:)
        raise NotImplementedError
      end

      def claim(task_id: nil, next_: false, ttl: nil, label: nil, steal: false)
        raise NotImplementedError
      end

      def release(task_id:, token:)
        raise NotImplementedError
      end

      def heartbeat(task_id:, token:, ttl: nil)
        raise NotImplementedError
      end

      def claims
        raise NotImplementedError
      end

      def available
        raise NotImplementedError
      end

      def adopt(task_id:, token: nil)
        raise NotImplementedError
      end

      def archive_task(task_id:, now: Time.now.utc)
        raise NotImplementedError
      end

      def children(parent_id:)
        raise NotImplementedError
      end

      def parent(task_id:)
        raise NotImplementedError
      end

      def tree
        raise NotImplementedError
      end

      def aggregate_status(task_id:)
        raise NotImplementedError
      end

      def current
        raise NotImplementedError
      end

      def use(task_id:)
        raise NotImplementedError
      end

      def rebuild_index
        raise NotImplementedError
      end

      def child_create(parent_id:, workflow:, title:, brief_body: nil)
        raise NotImplementedError
      end
    end
  end
end
