# frozen_string_literal: true

require_relative '../../result'
require_relative '../backend'
require_relative '../internal/aggregate_status'
require_relative '../internal/child_creator'
require_relative '../internal/children_lister'
require_relative '../internal/current_pointer'
require_relative '../internal/id_generator'
require_relative '../internal/index_reader'
require_relative '../internal/index_rebuilder'
require_relative '../internal/parent_resolver'
require_relative '../internal/paths'
require_relative '../internal/splitter'
require_relative '../internal/task_reader'
require_relative '../internal/task_writer'
require_relative '../internal/tree_builder'
require_relative '../internal/workflow_snapshot'

module Owl
  module Tasks
    module Backends
      class Filesystem
        include Owl::Tasks::Backend

        def initialize(root:)
          @root = root
        end

        def list
          paths_result = Internal::Paths.resolve(root: @root)
          return paths_result if paths_result.err?

          index_result = Internal::IndexReader.read(index_path: paths_result.value[:index])
          return index_result if index_result.err?

          Result.ok(
            index_path: paths_result.value[:index].to_s,
            schema_version: index_result.value[:schema_version],
            tasks: index_result.value[:tasks]
          )
        end

        def inspect_task(task_id:)
          paths_result = Internal::Paths.resolve(root: @root)
          return paths_result if paths_result.err?

          Internal::TaskReader.read(tasks_root: paths_result.value[:tasks], task_id: task_id)
        end

        def create(workflow:, title:, parent_id: nil, kind: nil)
          paths_result = Internal::Paths.resolve(root: @root)
          return paths_result if paths_result.err?

          snapshot_result = Internal::WorkflowSnapshot.snapshot(root: @root, workflow_key: workflow)
          return snapshot_result if snapshot_result.err?

          paths = paths_result.value
          task_id = Internal::IdGenerator.next_id(
            tasks_root: paths[:tasks],
            index_path: paths[:index]
          )

          payload = Internal::TaskWriter.build_payload(
            task_id: task_id,
            title: title.to_s,
            parent_id: parent_id,
            kind: kind,
            snapshot: snapshot_result.value
          )
          task_path = Internal::TaskWriter.write(
            tasks_root: paths[:tasks],
            task_id: task_id,
            payload: payload
          )

          rebuild_result = Internal::IndexRebuilder.rebuild(
            tasks_root: paths[:tasks],
            index_path: paths[:index]
          )
          return rebuild_result if rebuild_result.err?

          Result.ok(
            task_id: task_id,
            task_path: task_path.to_s,
            payload: payload,
            index_path: rebuild_result.value[:index_path]
          )
        end

        def archive_task(task_id:)
          raise NotImplementedError, 'Filesystem archive moves to backend in subtask #112'
        end

        def children(parent_id:)
          Internal::ChildrenLister.call(root: @root, parent_id: parent_id)
        end

        def parent(task_id:)
          Internal::ParentResolver.call(root: @root, task_id: task_id)
        end

        def tree
          Internal::TreeBuilder.call(root: @root)
        end

        def aggregate_status(task_id:)
          Internal::AggregateStatus.call(root: @root, task_id: task_id)
        end

        def current
          paths_result = Internal::Paths.resolve(root: @root)
          return paths_result if paths_result.err?

          pointer_result = Internal::CurrentPointer.read(local_state_root: paths_result.value[:local_state])
          return pointer_result if pointer_result.err?

          task_id = pointer_result.value[:task_id]
          read_result = Internal::TaskReader.read(
            tasks_root: paths_result.value[:tasks],
            task_id: task_id
          )
          return read_result if read_result.err?

          Result.ok(
            task_id: task_id,
            set_at: pointer_result.value[:set_at],
            pointer_path: pointer_result.value[:path],
            payload: read_result.value[:payload],
            task_path: read_result.value[:path]
          )
        end

        def use(task_id:)
          paths_result = Internal::Paths.resolve(root: @root)
          return paths_result if paths_result.err?

          read_result = Internal::TaskReader.read(
            tasks_root: paths_result.value[:tasks],
            task_id: task_id
          )
          return read_result if read_result.err?

          Internal::CurrentPointer.write(
            local_state_root: paths_result.value[:local_state],
            task_id: task_id
          )
        end

        def rebuild_index
          paths_result = Internal::Paths.resolve(root: @root)
          return paths_result if paths_result.err?

          Internal::IndexRebuilder.rebuild(
            tasks_root: paths_result.value[:tasks],
            index_path: paths_result.value[:index]
          )
        end

        def child_create(parent_id:, workflow:, title:)
          Internal::ChildCreator.call(
            root: @root,
            parent_id: parent_id,
            workflow: workflow,
            title: title,
            creator: method(:create_via_self)
          )
        end

        def split(task_id:, kind: 'composite_task')
          Internal::Splitter.call(root: @root, task_id: task_id, kind: kind)
        end

        private

        def create_via_self(root:, workflow:, title:, parent_id: nil, kind: nil)
          _ = root
          create(workflow: workflow, title: title, parent_id: parent_id, kind: kind)
        end
      end
    end
  end
end
