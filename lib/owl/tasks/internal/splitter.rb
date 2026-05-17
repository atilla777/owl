# frozen_string_literal: true

require_relative '../../result'
require_relative 'atomic_yaml_writer'
require_relative 'index_rebuilder'
require_relative 'paths'
require_relative 'task_reader'

module Owl
  module Tasks
    module Internal
      module Splitter
        DEFAULT_KIND = 'composite_task'
        ARCHIVED_STATUS = 'archived'

        module_function

        def call(root:, task_id:, kind: DEFAULT_KIND)
          paths_result = Paths.resolve(root: root)
          return paths_result if paths_result.err?

          paths = paths_result.value
          task_path = TaskReader.task_yaml_path(tasks_root: paths[:tasks], task_id: task_id)
          read_result = TaskReader.read(tasks_root: paths[:tasks], task_id: task_id)
          return read_result if read_result.err?

          payload = read_result.value[:payload]

          if payload['status'].to_s == ARCHIVED_STATUS
            return Result.err(
              code: :task_archived,
              message: "Task '#{task_id}' is archived and cannot be split.",
              details: { task_id: task_id.to_s }
            )
          end

          if payload['kind'].to_s == kind.to_s
            return Result.ok(task_id: task_id.to_s, changed: false, kind: kind.to_s, payload: payload)
          end

          payload['kind'] = kind.to_s
          AtomicYamlWriter.write(path: task_path, payload: payload)
          rebuild_result = IndexRebuilder.rebuild(tasks_root: paths[:tasks], index_path: paths[:index])
          return rebuild_result if rebuild_result.err?

          Result.ok(task_id: task_id.to_s, changed: true, kind: kind.to_s, payload: payload)
        end
      end
    end
  end
end
