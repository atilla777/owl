# frozen_string_literal: true

require_relative '../../result'
require_relative 'atomic_yaml_writer'
require_relative 'index_writer'
require_relative 'paths'
require_relative 'task_mutation_lock'
require_relative 'task_reader'
require_relative 'task_schema'

module Owl
  module Tasks
    module Internal
      # Sets the explicit task-level `status` field in task.yaml and refreshes
      # the index through the locked IndexWriter. Rejects statuses outside the
      # user-settable enum with :invalid_status before touching disk. The whole
      # read-modify-write runs under the per-task mutation lock so a concurrent
      # step/tracker mutation of the same task cannot clobber the status edit.
      module StatusWriter
        module_function

        def call(root:, task_id:, status:)
          status = status.to_s
          return invalid_status(status) unless TaskSchema.settable_status?(status)

          paths_result = Paths.resolve(root: root)
          return paths_result if paths_result.err?

          TaskMutationLock.with_lock(root: root, task_id: task_id) do
            read = TaskReader.read(tasks_root: paths_result.value[:tasks], task_id: task_id)
            next read if read.err?

            write_status(root: root, paths: paths_result.value, read: read, status: status)
          end
        end

        def write_status(root:, paths:, read:, status:)
          payload = read.value[:payload]
          payload['status'] = status

          schema = TaskSchema.validate(payload)
          return schema if schema.err?

          AtomicYamlWriter.write(path: read.value[:path], payload: payload)

          rebuild = IndexWriter.rebuild(root: root, tasks_root: paths[:tasks], index_path: paths[:index])
          return rebuild if rebuild.err?

          Result.ok(task_id: read.value[:payload]['id'].to_s, status: status)
        end

        def invalid_status(status)
          Result.err(
            code: :invalid_status,
            message: "Status must be one of #{TaskSchema::SETTABLE_STATUSES.inspect}, got #{status.inspect}.",
            details: { status: status, allowed: TaskSchema::SETTABLE_STATUSES }
          )
        end
      end
    end
  end
end
