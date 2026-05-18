# frozen_string_literal: true

require 'fileutils'
require 'pathname'

require_relative '../../../result'
require_relative '../atomic_yaml_writer'
require_relative '../index_rebuilder'
require_relative 'current_resetter'
require_relative 'path_rename'

module Owl
  module Tasks
    module Internal
      module Archive
        module Mover
          module_function

          def call(source_dir:, destination_path:, archived_payload:, task_yaml_relative:,
                   tasks_root:, index_path:, local_state_root:, task_id:)
            state = build_state(
              source_dir: source_dir,
              destination_path: destination_path,
              task_yaml_relative: task_yaml_relative,
              tasks_root: tasks_root,
              index_path: index_path,
              local_state_root: local_state_root,
              task_id: task_id
            )

            write_archived_yaml(state, archived_payload)

            move_err = rename_directory(state)
            return move_err if move_err

            index_err = rebuild_index(state)
            return index_err if index_err

            finalize_current(state)
          end

          def build_state(source_dir:, destination_path:, task_yaml_relative:,
                          tasks_root:, index_path:, local_state_root:, task_id:)
            source = Pathname.new(source_dir.to_s)
            {
              source: source,
              dest: Pathname.new(destination_path.to_s),
              task_yaml_source: source + task_yaml_relative,
              previous_task_yaml_bytes: nil,
              tasks_root: tasks_root,
              index_path: index_path,
              local_state_root: local_state_root,
              task_id: task_id
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
            Owl::Tasks::Internal::IndexRebuilder.rebuild(
              tasks_root: state[:tasks_root], index_path: state[:index_path]
            )
            nil
          rescue StandardError => e
            rollback_rename(state)
            restore_task_yaml(state)
            Result.err(
              code: :archive_index_rebuild_failed,
              message: "Failed to rebuild index after archive: #{e.message}",
              details: { reason: e.message, error_class: e.class.name }
            )
          end

          def finalize_current(state)
            reset_result = CurrentResetter.reset_if_matches(
              local_state_root: state[:local_state_root], task_id: state[:task_id]
            )
            if reset_result.err?
              rollback_index(state)
              restore_task_yaml(state)
              return Result.err(
                code: :archive_current_reset_failed,
                message: reset_result.message,
                details: reset_result.details
              )
            end

            Result.ok(
              current_reset: reset_result.value[:reset],
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

          def rollback_index(state)
            rollback_rename(state)
            Owl::Tasks::Internal::IndexRebuilder.rebuild(
              tasks_root: state[:tasks_root], index_path: state[:index_path]
            )
          rescue StandardError
            # Best-effort rollback; upstream error is already being reported.
          end
        end
      end
    end
  end
end
