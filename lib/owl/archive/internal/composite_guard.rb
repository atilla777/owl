# frozen_string_literal: true

require_relative '../../result'
require_relative '../../tasks/internal/index_reader'

module Owl
  module Archive
    module Internal
      module CompositeGuard
        COMPOSITE_KIND = 'composite_task'

        module_function

        def call(task_payload:, index_path:)
          kind = task_payload['kind'] || task_payload[:kind]
          return Result.ok(checked: false) unless kind.to_s == COMPOSITE_KIND

          task_id = (task_payload['id'] || task_payload[:id]).to_s

          index_result = Owl::Tasks::Internal::IndexReader.read(index_path: index_path)
          return index_result if index_result.err?

          entries = index_result.value[:tasks] || []
          children = entries.select { |entry| open_child?(entry, task_id) }
          open_children = children.map { |entry| entry['id'] }

          return Result.ok(checked: true) if open_children.empty?

          Result.err(
            code: :composite_with_open_children,
            message: "Composite task '#{task_id}' has #{open_children.length} non-archived child task(s).",
            details: { task_id: task_id, open_children: open_children }
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
