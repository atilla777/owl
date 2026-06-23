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

          index_children = entries.map { |entry| enrich(tasks_root: paths[:tasks], entry: entry) }
          children = merge_archived(root: root, parent_id: parent_id, index_children: index_children)
          Result.ok(parent_id: parent_id.to_s, children: children)
        end

        # Archived children disappear from tasks/index.yaml, so gather them from
        # the archive role through the public boundary and fold them in. Dedup by
        # task id, preferring the archived (terminal) entry.
        def merge_archived(root:, parent_id:, index_children:)
          archived = archived_children(root: root, parent_id: parent_id)
          return index_children if archived.empty?

          archived_ids = archived.map { |child| child[:id] }
          index_children.reject { |child| archived_ids.include?(child[:id]) } + archived
        end

        def archived_children(root:, parent_id:)
          # Lazy require through the public Archive boundary: a top-level require
          # would form a load-time cycle (archive/api -> tasks/api ->
          # backends/filesystem -> children_lister). By call time everything is
          # loaded, so this resolves without recursion.
          require_relative '../../archive/api'
          list_result = Owl::Archive::Api.list(root: root)
          return [] if list_result.err?

          (list_result.value[:archived] || [])
            .select { |entry| entry[:parent_id].to_s == parent_id.to_s && !entry[:parent_id].to_s.empty? }
            .map { |entry| archived_summary(entry) }
        end

        def archived_summary(entry)
          {
            id: entry[:task_id].to_s,
            title: entry[:title],
            workflow_key: entry[:workflow_key],
            status: 'archived',
            kind: entry[:kind],
            progress: empty_progress
          }
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
