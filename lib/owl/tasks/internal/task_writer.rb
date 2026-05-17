# frozen_string_literal: true

require 'pathname'
require 'time'

require_relative 'atomic_yaml_writer'
require_relative 'task_reader'

module Owl
  module Tasks
    module Internal
      module TaskWriter
        module_function

        def write(tasks_root:, task_id:, payload:)
          path = TaskReader.task_yaml_path(tasks_root: tasks_root, task_id: task_id)
          AtomicYamlWriter.write(path: path, payload: payload)
          path
        end

        def build_payload(task_id:, title:, snapshot:, parent_id: nil, kind: nil, now: Time.now.utc)
          {
            'id' => task_id,
            'title' => title,
            'workflow' => snapshot[:workflow],
            'kind' => kind || snapshot[:kind],
            'parent_id' => parent_id,
            'created_at' => now.iso8601,
            'steps' => snapshot[:steps],
            'artifacts' => snapshot[:artifacts]
          }
        end
      end
    end
  end
end
