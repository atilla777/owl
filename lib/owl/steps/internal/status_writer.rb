# frozen_string_literal: true

require_relative '../../result'
require_relative '../../tasks/internal/atomic_yaml_writer'
require_relative '../../tasks/internal/task_mutation_lock'
require_relative '../../tasks/internal/task_reader'

module Owl
  module Steps
    module Internal
      # Writes a single step's status/attributes into the owning task.yaml. The
      # read-modify-write of the whole `steps` array runs under the per-task
      # mutation lock (keyed by `root` + `task_id`) so a concurrent tracker
      # mutation (set-status/label/dep/...) of the same task cannot clobber the
      # step update, and vice-versa. Sequential same-task updates (e.g. a
      # `reopen --cascade`) each take and release the lock in turn — never
      # nested — so they do not self-deadlock the non-reentrant FileLock.
      module StatusWriter
        module_function

        def update(root:, tasks_root:, task_id:, step_id:, attributes:)
          Owl::Tasks::Internal::TaskMutationLock.with_lock(root: root, task_id: task_id) do
            locked_update(tasks_root: tasks_root, task_id: task_id, step_id: step_id, attributes: attributes)
          end
        end

        def locked_update(tasks_root:, task_id:, step_id:, attributes:)
          read = Owl::Tasks::Internal::TaskReader.read(tasks_root: tasks_root, task_id: task_id)
          return read if read.err?

          payload = read.value[:payload]
          steps = payload['steps'] || payload[:steps]
          unless steps.is_a?(Array)
            return Result.err(
              code: :task_steps_missing,
              message: "Task '#{task_id}' has no steps array in task.yaml.",
              details: { task_id: task_id }
            )
          end

          index = steps.index { |s| s.is_a?(Hash) && (s['id'] || s[:id]).to_s == step_id.to_s }
          unless index
            known = steps.filter_map { |s| (s['id'] || s[:id]).to_s if s.is_a?(Hash) }
            return Result.err(
              code: :unknown_step_id,
              message: "Step '#{step_id}' is not defined for task '#{task_id}'.",
              details: { task_id: task_id, step_id: step_id, known: known }
            )
          end

          updated_step = stringify_keys(steps[index]).merge(stringify_keys(attributes))
          steps[index] = updated_step

          payload['steps'] = steps
          Owl::Tasks::Internal::AtomicYamlWriter.write(
            path: Owl::Tasks::Internal::TaskReader.task_yaml_path(tasks_root: tasks_root, task_id: task_id),
            payload: payload
          )

          Result.ok(payload: payload, step: updated_step, path: read.value[:path])
        end

        def stringify_keys(hash)
          return {} unless hash.is_a?(Hash)

          hash.each_with_object({}) { |(k, v), memo| memo[k.to_s] = v }
        end
      end
    end
  end
end
