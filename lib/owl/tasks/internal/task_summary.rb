# frozen_string_literal: true

module Owl
  module Tasks
    module Internal
      # Single source of truth for the JSON shape of a task-list element shared by
      # `owl task available`, `owl task ready`, and `owl task list`. Projects a raw
      # index entry (string-keyed, identity under `id`) into the unified output
      # contract: identity under `task_id` plus the common core fields
      # (`task_id, title, kind, priority, created_at, status, workflow`), with
      # command-specific fields layered on top via `extra`.
      #
      # Output-only: the on-disk `tasks/index.yaml` keeps its `id` key. The rename
      # happens here, at serialization, never in storage. Centralising the shape
      # here is the whole point of the refactor — three commands used to build the
      # element independently and their contracts drifted apart.
      module TaskSummary
        module_function

        # @param entry [Hash] raw index entry (string keys; identity under 'id').
        # @param extra [Hash] command-specific fields (string keys) merged AFTER
        #   the core in canonical order. `available` passes
        #   `{ 'ready_step_ids' => [...], 'reason' => '...' }`; `ready`/`list` pass
        #   the tracker fields `{ 'parent_id', 'labels', 'blocked_by',
        #   'archived_at' }`.
        # @return [Hash] string-keyed hash in canonical key order.
        def project(entry, extra: {})
          {
            'task_id' => entry['id'].to_s,
            'title' => entry['title'],
            'kind' => entry['kind'],
            'priority' => priority_of(entry),
            'created_at' => entry['created_at'],
            'status' => entry['status'] || 'open',
            'workflow' => entry['workflow']
          }.merge(extra)
        end

        # Priority is normalised to an Integer so the value (and the rank it
        # drives) has identical semantics in every command; a legacy entry with a
        # missing/blank priority surfaces as 0.
        def priority_of(entry)
          raw = entry['priority']
          raw.is_a?(Integer) ? raw : raw.to_i
        end
      end
    end
  end
end
