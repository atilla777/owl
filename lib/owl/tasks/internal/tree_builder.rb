# frozen_string_literal: true

require_relative '../../result'
require_relative 'index_reader'
require_relative 'paths'

module Owl
  module Tasks
    module Internal
      module TreeBuilder
        MAX_DEPTH = 32

        module_function

        # When `root_id` is nil, return the full forest (every top-level task +
        # its descendants). When `root_id` names a task, return ONLY that task's
        # subtree (itself + descendants) as a single-element `tasks` array, so an
        # agent asking for one composite parent's tree does not have to filter
        # unrelated top-level tasks out of the response.
        def call(root:, root_id: nil)
          paths_result = Paths.resolve(root: root)
          return paths_result if paths_result.err?

          index_result = IndexReader.read(index_path: paths_result.value[:index])
          return index_result if index_result.err?

          entries = (index_result.value[:tasks] || []).grep(Hash)
          children_by_parent = entries.group_by { |e| e['parent_id'].to_s }

          roots = subtree_roots(entries: entries, root_id: root_id)
          return roots if roots.is_a?(Owl::Result::Err)

          warnings = []
          tree = roots.map { |entry| build_node(entry, children_by_parent, 0, Set.new, [], warnings) }
          Result.ok(tasks: tree, warnings: warnings)
        end

        # Resolve the set of root entries to expand: the whole forest for a nil
        # `root_id`, or just the single named entry (its subtree) otherwise.
        # Returns a `task_not_found` Err when `root_id` is unknown.
        def subtree_roots(entries:, root_id:)
          return entries.select { |e| e['parent_id'].to_s.empty? } if root_id.nil?

          entry = entries.find { |e| e['id'].to_s == root_id.to_s }
          return [entry] if entry

          Result.err(
            code: :task_not_found,
            message: "Task '#{root_id}' not found in tasks/index.yaml.",
            details: { task_id: root_id.to_s }
          )
        end

        def build_node(entry, children_by_parent, depth, seen, ancestor_ids, warnings)
          id = entry['id'].to_s
          path = (ancestor_ids + [id]).join('/')

          if seen.include?(id)
            warnings << { code: 'tree_cycle', at_path: path, cycle_id: id }
            return node_payload(entry).merge(children: [], truncated: true)
          end

          if depth >= MAX_DEPTH
            warnings << { code: 'tree_truncated', at_path: path, max_depth: MAX_DEPTH }
            return node_payload(entry).merge(children: [], truncated: true)
          end

          next_seen = seen + [id]
          next_ancestors = ancestor_ids + [id]
          kids = children_by_parent[id] || []
          node_payload(entry).merge(
            children: kids.map do |child|
              build_node(child, children_by_parent, depth + 1, next_seen, next_ancestors, warnings)
            end
          )
        end

        def node_payload(entry)
          {
            id: entry['id'].to_s,
            title: entry['title'],
            workflow_key: entry['workflow'],
            kind: entry['kind'],
            status: entry['status'] || 'todo',
            parent_id: entry['parent_id']
          }
        end
      end
    end
  end
end
