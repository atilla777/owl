# frozen_string_literal: true

require 'pathname'
require 'yaml'

require_relative 'atomic_yaml_writer'
require_relative '../../result'

module Owl
  module Tasks
    module Internal
      module CurrentPointer
        FILENAME = 'current.yaml'

        module_function

        def write(local_state_root:, task_id:)
          path = pointer_path(local_state_root: local_state_root)
          payload = { 'task_id' => task_id.to_s, 'set_at' => Time.now.utc.iso8601 }
          AtomicYamlWriter.write(path: path, payload: payload)
          Result.ok(task_id: task_id.to_s, path: path.to_s)
        end

        def read(local_state_root:)
          path = pointer_path(local_state_root: local_state_root)

          unless path.exist?
            return Result.err(
              code: :no_current_task,
              message: 'No current task is set. Run `owl task use <TASK-ID>` first.',
              details: { path: path.to_s }
            )
          end

          raw = YAML.safe_load(path.read, aliases: false, permitted_classes: [Time])
          unless raw.is_a?(Hash) && raw['task_id'].is_a?(String) && !raw['task_id'].empty?
            return Result.err(
              code: :no_current_task,
              message: "Current task pointer is invalid: #{path}",
              details: { path: path.to_s }
            )
          end

          Result.ok(task_id: raw['task_id'], set_at: raw['set_at'], path: path.to_s)
        rescue Psych::SyntaxError => e
          Result.err(code: :no_current_task, message: e.message, details: { path: path.to_s })
        end

        def pointer_path(local_state_root:)
          Pathname.new(local_state_root.to_s).join(FILENAME)
        end
      end
    end
  end
end
