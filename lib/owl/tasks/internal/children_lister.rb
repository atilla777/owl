# frozen_string_literal: true

require_relative '../../result'
require_relative '../../steps/internal/statuses'
require_relative 'index_reader'
require_relative 'paths'
require_relative 'task_reader'

module Owl
  module Tasks
    module Internal
      module ChildrenLister
        DONE_STATUSES = %w[done skipped].freeze

        module_function

        def call(root:, parent_id:)
          paths_result = Paths.resolve(root: root)
          return paths_result if paths_result.err?

          paths = paths_result.value
          index_result = IndexReader.read(index_path: paths[:index])
          return index_result if index_result.err?

          entries = (index_result.value[:tasks] || []).select do |entry|
            entry.is_a?(Hash) && entry['parent_id'].to_s == parent_id.to_s
          end

          children = entries.map { |entry| enrich(tasks_root: paths[:tasks], entry: entry) }
          Result.ok(parent_id: parent_id.to_s, children: children)
        end

        def enrich(tasks_root:, entry:)
          child_id = entry['id'].to_s
          read_result = TaskReader.read(tasks_root: tasks_root, task_id: child_id)
          return base_summary(entry).merge(progress: empty_progress, error: read_result.code.to_s) if read_result.err?

          payload = read_result.value[:payload]
          base_summary(entry).merge(progress: progress_for(payload['steps']))
        end

        def base_summary(entry)
          {
            id: entry['id'].to_s,
            title: entry['title'],
            workflow_key: entry['workflow'],
            status: entry['status'] || 'todo',
            kind: entry['kind']
          }
        end

        def progress_for(steps)
          steps = Array(steps)
          total = steps.size
          done = steps.count do |step|
            status = step.is_a?(Hash) ? (step['status'] || step[:status]) : nil
            DONE_STATUSES.include?(status.to_s)
          end
          pct = total.zero? ? 0.0 : ((done * 100.0) / total).round(1)
          { done: done, total: total, pct: pct }
        end

        def empty_progress
          { done: 0, total: 0, pct: 0.0 }
        end
      end
    end
  end
end
