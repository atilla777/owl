# frozen_string_literal: true

require_relative '../../result'
require_relative '../../internal/cycle_detector'
require_relative 'atomic_yaml_writer'
require_relative 'index_reader'
require_relative 'index_writer'
require_relative 'paths'
require_relative 'task_reader'
require_relative 'task_schema'

module Owl
  module Tasks
    module Internal
      # Mutates a task's canonical `blocked_by` dependency edge and recomputes
      # the locked index. `blocked_by` is the only stored direction; reverse
      # `blocks`/dependents are derived by scanning the index on read.
      #
      # `add` rejects self-dependencies, unknown tasks, and any edge that would
      # close a cycle in the `blocked_by` graph (index edges + the new edge),
      # reusing the shared Owl::Internal::CycleDetector. `remove` is a clean
      # no-op when the edge is absent.
      module DependencyWriter
        module_function

        def add(root:, task_id:, depends_on:)
          task_id = task_id.to_s
          depends_on = depends_on.to_s
          return self_dependency_error(task_id) if task_id == depends_on

          paths_result = Paths.resolve(root: root)
          return paths_result if paths_result.err?

          context = read_pair(paths: paths_result.value, task_id: task_id, depends_on: depends_on)
          return context if context.is_a?(Owl::Result::Err)

          read, blocked_by = context
          return Result.ok(task_id: task_id, blocked_by: blocked_by) if blocked_by.include?(depends_on)

          cycle = guard_acyclic(paths: paths_result.value, task_id: task_id, depends_on: depends_on,
                                blocked_by: blocked_by)
          return cycle if cycle

          payload = read.value[:payload]
          payload['blocked_by'] = blocked_by + [depends_on]
          persist(root: root, paths: paths_result.value, read: read, payload: payload)
        end

        def remove(root:, task_id:, depends_on:)
          task_id = task_id.to_s
          depends_on = depends_on.to_s

          paths_result = Paths.resolve(root: root)
          return paths_result if paths_result.err?

          read = TaskReader.read(tasks_root: paths_result.value[:tasks], task_id: task_id)
          return read if read.err?

          payload = read.value[:payload]
          blocked_by = normalize(payload['blocked_by'])
          return Result.ok(task_id: task_id, blocked_by: blocked_by) unless blocked_by.include?(depends_on)

          payload['blocked_by'] = blocked_by - [depends_on]
          persist(root: root, paths: paths_result.value, read: read, payload: payload)
        end

        def dependencies(root:, task_id:)
          task_id = task_id.to_s
          paths_result = Paths.resolve(root: root)
          return paths_result if paths_result.err?

          read = TaskReader.read(tasks_root: paths_result.value[:tasks], task_id: task_id)
          return read if read.err?

          Result.ok(
            task_id: task_id,
            blocked_by: normalize(read.value[:payload]['blocked_by']),
            blocks: compute_blocks(paths: paths_result.value, task_id: task_id)
          )
        end

        # Reads both endpoints, returning [read_result, normalized_blocked_by]
        # or the first Err encountered (unknown task on either side).
        def read_pair(paths:, task_id:, depends_on:)
          read = TaskReader.read(tasks_root: paths[:tasks], task_id: task_id)
          return read if read.err?

          dep_read = TaskReader.read(tasks_root: paths[:tasks], task_id: depends_on)
          return dep_read if dep_read.err?

          [read, normalize(read.value[:payload]['blocked_by'])]
        end

        # Builds the `blocked_by` adjacency from the index, splices in the
        # prospective edge, and returns a :dependency_cycle Err when it would
        # close a cycle (or the index-read Err); nil when acyclic.
        def guard_acyclic(paths:, task_id:, depends_on:, blocked_by:)
          index = IndexReader.read(index_path: paths[:index])
          return index if index.err?

          adjacency = {}
          Array(index.value[:tasks]).each do |entry|
            next unless entry.is_a?(Hash)

            adjacency[entry['id'].to_s] = normalize(entry['blocked_by'])
          end
          adjacency[task_id] = blocked_by + [depends_on]

          cycle = Owl::Internal::CycleDetector.detect(adjacency)
          cycle && cycle_error(task_id: task_id, depends_on: depends_on, cycle: cycle)
        end

        def compute_blocks(paths:, task_id:)
          index = IndexReader.read(index_path: paths[:index])
          return [] if index.err?

          dependents = Array(index.value[:tasks]).select do |entry|
            entry.is_a?(Hash) && normalize(entry['blocked_by']).include?(task_id)
          end
          dependents.map { |entry| entry['id'].to_s }.sort
        end

        def persist(root:, paths:, read:, payload:)
          schema = TaskSchema.validate(payload)
          return schema if schema.err?

          AtomicYamlWriter.write(path: read.value[:path], payload: payload)

          rebuild = IndexWriter.rebuild(root: root, tasks_root: paths[:tasks], index_path: paths[:index])
          return rebuild if rebuild.err?

          Result.ok(task_id: payload['id'].to_s, blocked_by: payload['blocked_by'])
        end

        def normalize(raw)
          Array(raw).map { |value| value.to_s.strip }.reject(&:empty?).uniq
        end

        def self_dependency_error(task_id)
          Result.err(
            code: :self_dependency,
            message: "Task '#{task_id}' cannot depend on itself.",
            details: { task_id: task_id }
          )
        end

        def cycle_error(task_id:, depends_on:, cycle:)
          Result.err(
            code: :dependency_cycle,
            message: "Adding dependency '#{task_id}' -> '#{depends_on}' would create a cycle: " \
                     "#{cycle.join(' -> ')}.",
            details: { task_id: task_id, depends_on: depends_on, cycle: cycle }
          )
        end
      end
    end
  end
end
