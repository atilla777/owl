# frozen_string_literal: true

require_relative '../../../result'
require_relative '../../../status/api'
require_relative '../../../tasks/api'

module Owl
  module Cli
    module Internal
      module Commands
        # View-model builder for `owl overview`. Reads exclusively through the
        # existing Api layer (`Tasks::Api.tree`/`.list`/`.current_task_id` and
        # `Status::Api.show`) — no direct FS access to `.owl/`/`tasks/`/`docs/`
        # (architecture §4). Enriches the plain `task tree` forest with per-node
        # progress, current-task highlight and unmet-dependency annotations.
        module OverviewData
          # Task statuses hidden from the default forest — surfaced only with
          # `--all`. Mirrors the brief: archived/abandoned are the terminal
          # states pruned by default.
          HIDDEN_STATUSES = %w[archived abandoned].freeze

          # A dependency counts as satisfied when the blocking task is terminally
          # complete OR absent from the index (archived out / dangling ref).
          # Mirrors the domain ReadyScanner's `deps_complete?` predicate — kept as
          # a local copy so the CLI layer does not reach into a domain private.
          DEP_COMPLETE_STATUSES = %w[done archived].freeze

          EMPTY_PROGRESS = { done: 0, total: 0, pct: 0.0 }.freeze

          module_function

          def build(root:, task_id: nil, all: false)
            tree_result = Owl::Tasks::Api.tree(root: root, root_id: task_id)
            return tree_result if tree_result.err?

            list_result = Owl::Tasks::Api.list(root: root)
            return list_result if list_result.err?

            index = index_by_id(list_result.value[:tasks])
            current_id = resolve_current_id(root: root)
            nodes = enrich_forest(tree_result.value[:tasks], root: root, index: index,
                                                             current_id: current_id, all: all)

            Owl::Result.ok(
              tree: nodes,
              current_task_id: current_id,
              warnings: Array(tree_result.value[:warnings])
            )
          end

          # A broken current pointer (task deleted/archived) must not crash the
          # overview — render without a highlight instead.
          def resolve_current_id(root:)
            result = Owl::Tasks::Api.current_task_id(root: root)
            result.ok? ? result.value : nil
          end

          def index_by_id(tasks)
            Array(tasks).each_with_object({}) do |entry, acc|
              next unless entry.is_a?(Hash)

              acc[entry['task_id'].to_s] = entry
            end
          end

          def enrich_forest(nodes, root:, index:, current_id:, all:)
            Array(nodes).filter_map do |node|
              next if hidden?(node, all: all)

              enrich_node(node, root: root, index: index, current_id: current_id, all: all)
            end
          end

          def enrich_node(node, root:, index:, current_id:, all:)
            id = node[:id].to_s
            entry = index[id] || {}
            blocked_by = Array(entry['blocked_by']).map(&:to_s)
            {
              id: id,
              title: node[:title],
              workflow_key: node[:workflow_key],
              kind: node[:kind],
              status: node[:status],
              parent_id: node[:parent_id],
              progress: progress_for(root: root, task_id: id),
              current: id == current_id.to_s,
              blocked_by: blocked_by,
              unmet_deps: unmet_deps(blocked_by, index),
              children: enrich_forest(node[:children], root: root, index: index,
                                                       current_id: current_id, all: all)
            }
          end

          def hidden?(node, all:)
            return false if all

            HIDDEN_STATUSES.include?(node[:status].to_s)
          end

          def progress_for(root:, task_id:)
            status = Owl::Status::Api.show(root: root, task_id: task_id)
            return EMPTY_PROGRESS if status.err?

            status.value[:progress] || EMPTY_PROGRESS
          end

          def unmet_deps(blocked_by, index)
            blocked_by.reject { |dep| dep_complete?(dep, index) }
          end

          def dep_complete?(dep, index)
            entry = index[dep.to_s]
            return true if entry.nil?

            DEP_COMPLETE_STATUSES.include?(entry['status'].to_s)
          end
        end
      end
    end
  end
end
