# frozen_string_literal: true

require 'pathname'
require 'yaml'

require_relative '../../result'

module Owl
  module Tasks
    module Internal
      module TaskReader
        TASK_FILENAME = 'task.yaml'

        module_function

        def read(tasks_root:, task_id:)
          path = task_yaml_path(tasks_root: tasks_root, task_id: task_id)

          unless path.exist?
            return Result.err(
              code: :task_not_found,
              message: "Task '#{task_id}' not found at #{path}",
              details: { task_id: task_id.to_s, path: path.to_s }
            )
          end

          raw = YAML.safe_load(path.read, aliases: false, permitted_classes: [Time])
          unless raw.is_a?(Hash)
            return Result.err(
              code: :task_yaml_invalid,
              message: "task.yaml is not a YAML mapping: #{path}",
              details: { task_id: task_id.to_s, path: path.to_s }
            )
          end

          Result.ok(payload: raw, path: path.to_s)
        rescue Psych::SyntaxError => e
          Result.err(
            code: :task_yaml_invalid,
            message: e.message,
            details: { task_id: task_id.to_s, path: path.to_s }
          )
        end

        def task_yaml_path(tasks_root:, task_id:)
          Pathname.new(tasks_root.to_s).join(task_id.to_s, TASK_FILENAME)
        end
      end
    end
  end
end
