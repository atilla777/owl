# frozen_string_literal: true

require 'pathname'
require 'yaml'

require_relative '../../result'
require_relative 'id_generator'
require_relative 'paths'
require_relative 'task_reader'

module Owl
  module Tasks
    module Internal
      # Read-only referential-integrity scanner over the on-disk task set. It
      # reads the authoritative per-task `task.yaml` files (not the projected
      # index) and reports edges that point at tasks which no longer exist:
      #
      # - `orphans`       a task whose non-empty `parent_id` names a task dir
      #                   that is absent (e.g. a composite parent deleted
      #                   non-recursively in an older Owl, before delete grew
      #                   its `task_has_children` guard).
      # - `dangling_deps` a task whose `blocked_by` lists ids with no task dir,
      #                   which would silently keep the task "ready" forever or
      #                   confuse dependency readers.
      #
      # Never mutates anything — `owl doctor` surfaces these report-only so a
      # human decides whether to re-parent, delete the subtree, or scrub the
      # edge (`owl task dep remove`).
      module IntegrityScanner
        module_function

        def scan(root:)
          paths_result = Paths.resolve(root: root)
          return paths_result if paths_result.err?

          entries = read_entries(tasks_root: paths_result.value[:tasks])
          ids = entries.to_set { |e| e[:id] }

          Result.ok(
            orphans: orphans(entries: entries, ids: ids),
            dangling_deps: dangling_deps(entries: entries, ids: ids)
          )
        end

        def orphans(entries:, ids:)
          entries.filter_map do |entry|
            parent = entry[:parent_id]
            next if parent.empty? || ids.include?(parent)

            { task_id: entry[:id], parent_id: parent }
          end
        end

        def dangling_deps(entries:, ids:)
          entries.filter_map do |entry|
            missing = entry[:blocked_by].reject { |dep| ids.include?(dep) }
            next if missing.empty?

            { task_id: entry[:id], missing: missing }
          end
        end

        # One normalized record per task dir: { id, parent_id, blocked_by }.
        # Reads task.yaml directly (unreadable/corrupt files are skipped) so the
        # scan is independent of index drift.
        def read_entries(tasks_root:)
          dir = Pathname.new(tasks_root.to_s)
          return [] unless dir.directory?

          dir.children.sort.filter_map do |child|
            next unless child.directory? && IdGenerator.parse(child.basename.to_s)

            yaml = child.join(TaskReader::TASK_FILENAME)
            next unless yaml.file?

            raw = YAML.safe_load(yaml.read, aliases: false, permitted_classes: [Time])
            next unless raw.is_a?(Hash)

            {
              id: child.basename.to_s,
              parent_id: raw['parent_id'].to_s,
              blocked_by: Array(raw['blocked_by']).map(&:to_s).reject(&:empty?)
            }
          rescue Psych::SyntaxError
            next
          end
        end
      end
    end
  end
end
