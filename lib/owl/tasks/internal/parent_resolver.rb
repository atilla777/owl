# frozen_string_literal: true

require_relative '../../result'
require_relative 'paths'
require_relative 'task_reader'

module Owl
  module Tasks
    module Internal
      module ParentResolver
        module_function

        def call(root:, task_id:)
          paths_result = Paths.resolve(root: root)
          return paths_result if paths_result.err?

          tasks_root = paths_result.value[:tasks]
          task_result = TaskReader.read(tasks_root: tasks_root, task_id: task_id)
          return task_result if task_result.err?

          parent_id = task_result.value[:payload]['parent_id']
          return Result.ok(task_id: task_id.to_s, parent: nil) if parent_id.to_s.empty?

          parent_result = TaskReader.read(tasks_root: tasks_root, task_id: parent_id)
          if parent_result.err?
            return Result.ok(
              task_id: task_id.to_s,
              parent: { id: parent_id.to_s, missing: true, error: parent_result.code.to_s }
            )
          end

          payload = parent_result.value[:payload]
          Result.ok(
            task_id: task_id.to_s,
            parent: {
              id: payload['id'].to_s,
              title: payload['title'],
              workflow_key: payload.dig('workflow', 'key'),
              kind: payload['kind'],
              status: payload['status']
            }
          )
        end
      end
    end
  end
end
