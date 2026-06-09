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

        def build_payload(task_id:, title:, snapshot:, parent_id: nil, kind: nil, step_variants: nil,
                          priority: 0, now: Time.now.utc)
          payload = {
            'id' => task_id,
            'title' => title,
            'workflow' => snapshot[:workflow],
            'kind' => kind || snapshot[:kind],
            'parent_id' => parent_id,
            'priority' => priority,
            'created_at' => now.iso8601,
            'steps' => snapshot[:steps],
            'artifacts' => snapshot[:artifacts]
          }
          normalized = normalize_step_variants(step_variants)
          payload['step_variants'] = normalized unless normalized.empty?
          payload
        end

        def normalize_step_variants(raw)
          return {} unless raw.is_a?(Hash)

          raw.each_with_object({}) do |(k, v), acc|
            next if k.nil? || v.nil?

            key = k.to_s.strip
            val = v.to_s.strip
            next if key.empty? || val.empty?

            acc[key] = val
          end
        end
      end
    end
  end
end
