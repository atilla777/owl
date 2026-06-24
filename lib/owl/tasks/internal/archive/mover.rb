# frozen_string_literal: true

require 'fileutils'
require 'pathname'

require_relative '../../../result'
require_relative '../atomic_yaml_writer'
require_relative '../index_writer'
require_relative 'path_rename'

module Owl
  module Tasks
    module Internal
      module Archive
        module Mover
          module_function

          def call(source_dir:, destination_path:, archived_payload:, task_yaml_relative:,
                   tasks_root:, index_path:, task_id:, root:)
            state = build_state(
              source_dir: source_dir,
              destination_path: destination_path,
              task_yaml_relative: task_yaml_relative,
              tasks_root: tasks_root,
              index_path: index_path,
              task_id: task_id,
              root: root
            )

            write_archived_yaml(state, archived_payload)

            move_err = rename_directory(state)
            return move_err if move_err

            index_err = rebuild_index(state)
            return index_err if index_err

            finalize_current(state)
          end

          def build_state(source_dir:, destination_path:, task_yaml_relative:,
                          tasks_root:, index_path:, task_id:, root:)
            source = Pathname.new(source_dir.to_s)
            {
              source: source,
              dest: Pathname.new(destination_path.to_s),
              task_yaml_source: source + task_yaml_relative,
              previous_task_yaml_bytes: nil,
              tasks_root: tasks_root,
              index_path: index_path,
              task_id: task_id,
              root: root
            }
          end

          def write_archived_yaml(state, archived_payload)
            path = state[:task_yaml_source]
            state[:previous_task_yaml_bytes] = path.exist? ? path.read : nil
            Owl::Tasks::Internal::AtomicYamlWriter.write(path: path, payload: archived_payload)
          end

          def rename_directory(state)
            FileUtils.mkdir_p(state[:dest].dirname.to_s)
            result = PathRename.call(source: state[:source], dest: state[:dest])
            return nil if result.ok?

            restore_task_yaml(state)
            Result.err(
              code: :archive_move_failed,
              message: "Failed to move '#{state[:source]}' to '#{state[:dest]}': #{result.details[:reason]}",
              details: {
                reason: result.details[:reason], error_class: result.details[:error_class],
                source: state[:source].to_s, destination: state[:dest].to_s
              }
            )
          end

          def rebuild_index(state)
            result = Owl::Tasks::Internal::IndexWriter.rebuild(
              root: state[:root], tasks_root: state[:tasks_root], index_path: state[:index_path]
            )
            return archive_index_failed(state, result.message) if result.err?

            nil
          rescue StandardError => e
            archive_index_failed(state, e.message, error_class: e.class.name)
          end

          def archive_index_failed(state, reason, error_class: nil)
            rollback_rename(state)
            restore_task_yaml(state)
            Result.err(
              code: :archive_index_rebuild_failed,
              message: "Failed to rebuild index after archive: #{reason}",
              details: { reason: reason, error_class: error_class }
            )
          end

          # The current-task pointer is intentionally NOT reset here. An archived
          # task stays the current task so the workflow can finish its
          # post-archive steps (e.g. `commit_push`). The pointer is reset later,
          # when the final step completes (see Steps::Api.complete).
          def finalize_current(state)
            Result.ok(
              current_reset: false,
              previous_task_yaml_bytes: state[:previous_task_yaml_bytes]
            )
          end

          def restore_task_yaml(state)
            previous = state[:previous_task_yaml_bytes]
            return if previous.nil?

            path = state[:task_yaml_source]
            path.write(previous) if path.exist?
          end

          def rollback_rename(state)
            return unless state[:dest].exist?

            PathRename.call(source: state[:dest], dest: state[:source])
          end
        end
      end
    end
  end
end
