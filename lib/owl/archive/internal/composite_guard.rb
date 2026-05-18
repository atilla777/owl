# frozen_string_literal: true

require_relative '../../result'
require_relative '../../tasks/internal/index_reader'
require_relative 'child_readiness_checker'

module Owl
  module Archive
    module Internal
      module CompositeGuard
        COMPOSITE_KIND = 'composite_task'

        module_function

        def call(task_payload:, index_path:, subtree_mode: false, tasks_root: nil)
          kind = task_payload['kind'] || task_payload[:kind]
          return Result.ok(checked: false) unless kind.to_s == COMPOSITE_KIND

          task_id = (task_payload['id'] || task_payload[:id]).to_s

          index_result = Owl::Tasks::Internal::IndexReader.read(index_path: index_path)
          return index_result if index_result.err?

          entries = index_result.value[:tasks] || []
          open_children_ids = entries.select { |entry| open_child?(entry, task_id) }
                                     .map { |entry| entry['id'] }

          return Result.ok(checked: true) if open_children_ids.empty?

          if subtree_mode
            subtree_check(
              task_id: task_id,
              open_children_ids: open_children_ids,
              tasks_root: tasks_root
            )
          else
            Result.err(
              code: :composite_with_open_children,
              message: "Composite task '#{task_id}' has #{open_children_ids.length} non-archived child task(s).",
              details: { task_id: task_id, open_children: open_children_ids }
            )
          end
        end

        def subtree_check(task_id:, open_children_ids:, tasks_root:)
          unready = open_children_ids.filter_map do |child_id|
            check = ChildReadinessChecker.call(tasks_root: tasks_root, task_id: child_id)
            next { id: child_id, error: check.code.to_s } if check.err?
            next nil if check.value[:ready]

            { id: child_id, missing_steps: check.value[:missing_steps] }
          end

          return Result.ok(checked: true, bypass: true, ready_children: open_children_ids) if unready.empty?

          Result.err(
            code: :composite_with_unready_children,
            message: "Composite task '#{task_id}' has #{unready.length} child task(s) not ready for archive.",
            details: { task_id: task_id, unready_children: unready }
          )
        end

        def open_child?(entry, parent_task_id)
          return false unless entry.is_a?(Hash)
          return false unless entry['parent_id'].to_s == parent_task_id

          entry['status'].to_s != 'archived'
        end
      end
    end
  end
end
