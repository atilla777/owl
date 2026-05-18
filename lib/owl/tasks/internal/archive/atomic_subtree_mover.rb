# frozen_string_literal: true

require 'fileutils'
require 'pathname'
require 'securerandom'

require_relative '../../../result'
require_relative '../atomic_yaml_writer'
require_relative '../index_rebuilder'
require_relative '../task_reader'
require_relative 'current_resetter'
require_relative 'path_rename'

module Owl
  module Tasks
    module Internal
      module Archive
        module AtomicSubtreeMover
          STAGING_DIRNAME = '.archive-staging'

          module_function

          def call(plans:, tasks_root:, index_path:, local_state_root:)
            state = init_state(
              plans: plans,
              tasks_root: tasks_root,
              index_path: index_path,
              local_state_root: local_state_root
            )

            err = move_into_staging(state)
            return rollback(state, failed_at: :move_into_staging, cause: err) if err

            err = commit(state)
            return rollback(state, failed_at: :commit, cause: err) if err

            err = finalize(state)
            return rollback(state, failed_at: :finalize, cause: err) if err

            cleanup_staging(state)
            ok_result(state)
          end

          def init_state(plans:, tasks_root:, index_path:, local_state_root:)
            txn_id = SecureRandom.hex(8)
            {
              plans: plans,
              tasks_root: Pathname.new(tasks_root.to_s),
              index_path: index_path,
              local_state_root: local_state_root,
              txn_id: txn_id,
              staging_root: Pathname.new(tasks_root.to_s) + STAGING_DIRNAME + txn_id,
              staged_renames: [],
              committed_renames: [],
              task_yaml_backups: {},
              current_resets: []
            }
          end

          def move_into_staging(state)
            FileUtils.mkdir_p(state[:staging_root].to_s)

            state[:plans].each do |plan|
              backup_err = backup_and_rewrite_task_yaml(state, plan)
              return backup_err if backup_err

              staged_dir = state[:staging_root] + plan[:task_id].to_s
              rename_result = PathRename.call(source: plan[:source_dir], dest: staged_dir)
              return rename_result if rename_result.err?

              state[:staged_renames] << {
                task_id: plan[:task_id].to_s,
                original: Pathname.new(plan[:source_dir].to_s),
                staged: staged_dir
              }
            end

            nil
          end

          def backup_and_rewrite_task_yaml(state, plan)
            source_dir = Pathname.new(plan[:source_dir].to_s)
            yaml_path = source_dir + Owl::Tasks::Internal::TaskReader::TASK_FILENAME
            state[:task_yaml_backups][plan[:task_id].to_s] = yaml_path.exist? ? yaml_path.read : nil
            Owl::Tasks::Internal::AtomicYamlWriter.write(path: yaml_path, payload: plan[:archived_payload])
            nil
          rescue StandardError => e
            Result.err(
              code: :task_yaml_rewrite_failed,
              message: "Failed to rewrite task.yaml for '#{plan[:task_id]}': #{e.message}",
              details: { task_id: plan[:task_id].to_s, error_class: e.class.name, reason: e.message }
            )
          end

          def commit(state)
            state[:staged_renames].each do |entry|
              plan = state[:plans].find { |p| p[:task_id].to_s == entry[:task_id] }
              dest = Pathname.new(plan[:destination_path].to_s)
              FileUtils.mkdir_p(dest.dirname.to_s)

              rename_result = PathRename.call(source: entry[:staged], dest: dest)
              return rename_result if rename_result.err?

              state[:committed_renames] << {
                task_id: entry[:task_id],
                staged: entry[:staged],
                dest: dest
              }
            end

            nil
          end

          def finalize(state)
            rebuild_result = Owl::Tasks::Internal::IndexRebuilder.rebuild(
              tasks_root: state[:tasks_root], index_path: state[:index_path]
            )
            return rebuild_result if rebuild_result.is_a?(Result::Err) && rebuild_result.err?

            state[:plans].each do |plan|
              reset_result = CurrentResetter.reset_if_matches(
                local_state_root: state[:local_state_root], task_id: plan[:task_id]
              )
              return reset_result if reset_result.err?

              next unless reset_result.value[:reset]

              state[:current_resets] << {
                task_id: plan[:task_id].to_s,
                path: reset_result.value[:path],
                previous_bytes: reset_result.value[:previous_bytes]
              }
            end

            nil
          end

          def rollback(state, failed_at:, cause:)
            undo_current_resets(state)
            undo_committed_renames(state)
            undo_staged_renames(state)
            restore_task_yamls(state)
            rebuild_index_after_rollback(state) if failed_at == :finalize
            cleanup_staging(state)

            rollback_error(state: state, failed_at: failed_at, cause: cause)
          end

          def undo_current_resets(state)
            state[:current_resets].reverse_each do |entry|
              CurrentResetter.restore(path: entry[:path], previous_bytes: entry[:previous_bytes])
            end
          end

          def undo_committed_renames(state)
            state[:committed_renames].reverse_each do |entry|
              PathRename.call(source: entry[:dest], dest: entry[:staged])
            end
          end

          def undo_staged_renames(state)
            state[:staged_renames].reverse_each do |entry|
              PathRename.call(source: entry[:staged], dest: entry[:original])
            end
          end

          def restore_task_yamls(state)
            state[:task_yaml_backups].each do |task_id, bytes|
              next if bytes.nil?

              yaml_path = state[:tasks_root] + task_id.to_s + Owl::Tasks::Internal::TaskReader::TASK_FILENAME
              yaml_path.write(bytes) if yaml_path.exist?
            end
          end

          def rebuild_index_after_rollback(state)
            Owl::Tasks::Internal::IndexRebuilder.rebuild(
              tasks_root: state[:tasks_root], index_path: state[:index_path]
            )
          end

          def rollback_error(state:, failed_at:, cause:)
            Result.err(
              code: :composite_archive_failed,
              message: "Composite archive failed at #{failed_at}: #{cause.message}",
              details: {
                txn_id: state[:txn_id],
                rolled_back: true,
                failed_at: failed_at,
                cause: { code: cause.code, message: cause.message, details: cause.details }
              }
            )
          end

          def cleanup_staging(state)
            staging_root = state[:staging_root]
            return unless staging_root.exist?

            staging_root.rmdir if staging_root.children.empty?
            parent = staging_root.dirname
            parent.rmdir if parent.exist? && parent.children.empty?
          rescue SystemCallError
            # Best-effort; not critical to leave stale empty staging directories.
          end

          def ok_result(state)
            moved_paths = state[:plans].to_h do |plan|
              [plan[:task_id].to_s, plan[:destination_path].to_s]
            end

            Result.ok(
              txn_id: state[:txn_id],
              archived: state[:plans].map { |p| p[:task_id].to_s },
              moved_paths: moved_paths,
              rolled_back: false,
              current_reset: state[:current_resets].map { |r| r[:task_id] }
            )
          end
        end
      end
    end
  end
end
