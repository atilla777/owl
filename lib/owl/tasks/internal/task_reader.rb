# frozen_string_literal: true

require 'pathname'
require 'yaml'

require_relative '../../result'

module Owl
  module Tasks
    module Internal
      module TaskReader
        TASK_FILENAME = 'task.yaml'
        # Archived tasks are relocated under `<tasks_root>/archive/<date>-<id>-<slug>/`
        # by the archive flow (see Archive::Mover). The default and standard
        # storage profiles both nest the archive role there, and the index
        # rebuilder already relies on this convention by skipping the `archive`
        # subdir. Keeping archived tasks resolvable lets the workflow finish its
        # post-archive steps (e.g. `commit_push`) after the directory has moved.
        ARCHIVE_SUBDIR = 'archive'

        module_function

        def read(tasks_root:, task_id:)
          path = task_yaml_path(tasks_root: tasks_root, task_id: task_id)

          unless path.exist?
            return Result.err(
              code: :task_not_found,
              message: "Task '#{task_id}' not found at #{path}",
              details: { task_id: task_id.to_s, path: path.to_s }
            )
          end

          raw = YAML.safe_load(path.read, aliases: false, permitted_classes: [Time])
          unless raw.is_a?(Hash)
            return Result.err(
              code: :task_yaml_invalid,
              message: "task.yaml is not a YAML mapping: #{path}",
              details: { task_id: task_id.to_s, path: path.to_s }
            )
          end

          Result.ok(payload: raw, path: path.to_s)
        rescue Psych::SyntaxError => e
          Result.err(
            code: :task_yaml_invalid,
            message: e.message,
            details: { task_id: task_id.to_s, path: path.to_s }
          )
        end

        # Resolves to the live task.yaml when the task is still in the work zone,
        # otherwise to its archived location. Falls back to the live path (which
        # then simply does not exist) so callers that create a task or report
        # `task_not_found` keep their existing behaviour.
        def task_yaml_path(tasks_root:, task_id:)
          live = live_task_yaml_path(tasks_root: tasks_root, task_id: task_id)
          return live if live.file?

          archived_task_yaml_path(tasks_root: tasks_root, task_id: task_id) || live
        end

        def live_task_yaml_path(tasks_root:, task_id:)
          Pathname.new(tasks_root.to_s).join(task_id.to_s, TASK_FILENAME)
        end

        # Scans `<tasks_root>/archive/*` for a directory whose task.yaml carries
        # the matching id. The directory name embeds the id between dashes
        # (`<date>-<id>-<slug>`), so a boundary-anchored prefilter avoids reading
        # every archived task before confirming by the authoritative id field.
        def archived_task_yaml_path(tasks_root:, task_id:)
          archive_root = Pathname.new(tasks_root.to_s).join(ARCHIVE_SUBDIR)
          return nil unless archive_root.directory?

          id = task_id.to_s
          token = /(?:\A|-)#{Regexp.escape(id)}(?:-|\z)/
          archive_root.children.find do |dir|
            next false unless dir.directory? && dir.basename.to_s.match?(token)

            candidate = dir.join(TASK_FILENAME)
            candidate.file? && archived_task_id(candidate) == id
          end&.join(TASK_FILENAME)
        end

        def archived_task_id(candidate)
          raw = YAML.safe_load(candidate.read, aliases: false, permitted_classes: [Time])
          raw.is_a?(Hash) ? raw['id'].to_s : nil
        rescue Psych::SyntaxError
          nil
        end
      end
    end
  end
end
