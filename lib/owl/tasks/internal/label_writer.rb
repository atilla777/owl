# frozen_string_literal: true

require_relative '../../result'
require_relative 'atomic_yaml_writer'
require_relative 'index_writer'
require_relative 'paths'
require_relative 'task_reader'
require_relative 'task_schema'

module Owl
  module Tasks
    module Internal
      # Adds / removes a single label on a task and refreshes the index through
      # the locked IndexWriter. `add` is idempotent (trimmed, no duplicates);
      # `remove` of an absent label is a clean no-op.
      module LabelWriter
        module_function

        def add(root:, task_id:, label:)
          mutate(root: root, task_id: task_id) do |labels|
            trimmed = label.to_s.strip
            labels << trimmed if !trimmed.empty? && !labels.include?(trimmed)
            labels
          end
        end

        def remove(root:, task_id:, label:)
          mutate(root: root, task_id: task_id) do |labels|
            labels - [label.to_s.strip]
          end
        end

        def mutate(root:, task_id:)
          paths_result = Paths.resolve(root: root)
          return paths_result if paths_result.err?

          read = TaskReader.read(tasks_root: paths_result.value[:tasks], task_id: task_id)
          return read if read.err?

          payload = read.value[:payload]
          payload['labels'] = yield(normalize(payload['labels']))

          persist(root: root, paths: paths_result.value, read: read, payload: payload)
        end

        def persist(root:, paths:, read:, payload:)
          schema = TaskSchema.validate(payload)
          return schema if schema.err?

          AtomicYamlWriter.write(path: read.value[:path], payload: payload)

          rebuild = IndexWriter.rebuild(root: root, tasks_root: paths[:tasks], index_path: paths[:index])
          return rebuild if rebuild.err?

          Result.ok(task_id: payload['id'].to_s, labels: payload['labels'])
        end

        def normalize(raw)
          Array(raw).map { |value| value.to_s.strip }.reject(&:empty?).uniq
        end
      end
    end
  end
end
