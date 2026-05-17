# frozen_string_literal: true

require_relative '../../result'
require_relative 'children_lister'
require_relative 'paths'
require_relative 'task_reader'

module Owl
  module Tasks
    module Internal
      module AggregateStatus
        COMPOSITE_KIND = 'composite_task'
        DONE_STATUSES = %w[done skipped].freeze
        BLOCKER_STATUSES = %w[blocked failed].freeze
        READY_OR_ARCHIVED_STATES = %w[done archived].freeze

        module_function

        def call(root:, task_id:)
          paths_result = Paths.resolve(root: root)
          return paths_result if paths_result.err?

          task_result = TaskReader.read(tasks_root: paths_result.value[:tasks], task_id: task_id)
          return task_result if task_result.err?

          payload = task_result.value[:payload]
          unless payload['kind'].to_s == COMPOSITE_KIND
            return Result.err(
              code: :not_a_composite_task,
              message: "Task '#{task_id}' is not a composite_task (kind=#{payload['kind'].inspect}).",
              details: { task_id: task_id.to_s, kind: payload['kind'] }
            )
          end

          children_result = ChildrenLister.call(root: root, parent_id: task_id)
          return children_result if children_result.err?

          children = children_result.value[:children]
          by_child = children.map do |child|
            state = child_state(root: paths_result.value[:tasks], child: child)
            { id: child[:id], state: state, status: child[:status] }
          end

          Result.ok(
            task_id: task_id.to_s,
            aggregate: aggregate_state(by_child),
            by_child: by_child,
            by_state: count_by_state(by_child)
          )
        end

        def child_state(root:, child:)
          return 'archived' if child[:status].to_s == 'archived'

          read_result = TaskReader.read(tasks_root: root, task_id: child[:id])
          return 'in_progress' if read_result.err?

          steps = Array(read_result.value[:payload]['steps'])
          statuses = steps.map { |s| (s.is_a?(Hash) ? s['status'] : nil).to_s }
          return 'blocked' if statuses.any? { |s| BLOCKER_STATUSES.include?(s) }
          return 'done' if !statuses.empty? && statuses.all? { |s| DONE_STATUSES.include?(s) }

          'in_progress'
        end

        def aggregate_state(by_child)
          return 'open' if by_child.empty?
          return 'blocked' if by_child.any? { |c| c[:state] == 'blocked' }
          return 'done' if by_child.all? { |c| c[:state] == 'archived' }
          return 'ready' if by_child.all? { |c| READY_OR_ARCHIVED_STATES.include?(c[:state]) }

          'open'
        end

        def count_by_state(by_child)
          by_child.each_with_object(Hash.new(0)) { |c, memo| memo[c[:state]] += 1 }
        end
      end
    end
  end
end
