# frozen_string_literal: true

require 'fileutils'
require 'pathname'
require 'yaml'

require_relative '../../result'
require_relative 'archive/claim_resetter'
require_relative 'atomic_yaml_writer'
require_relative 'id_generator'
require_relative 'index_writer'
require_relative 'paths'
require_relative 'task_reader'

module Owl
  module Tasks
    module Internal
      module Deleter
        module_function

        def call(root:, task_id:)
          paths_result = Paths.resolve(root: root)
          return paths_result if paths_result.err?

          task_dir = Pathname.new(paths_result.value[:tasks].to_s) / task_id.to_s
          unless task_dir.directory?
            return Result.err(
              code: :task_not_found,
              message: "Task '#{task_id}' not found under #{paths_result.value[:tasks]}.",
              details: { task_id: task_id.to_s }
            )
          end

          FileUtils.rm_rf(task_dir.to_s)
          clean_dangling_refs(tasks_root: paths_result.value[:tasks], deleted_id: task_id.to_s)

          rebuild = IndexWriter.rebuild(
            root: root,
            tasks_root: paths_result.value[:tasks],
            index_path: paths_result.value[:index]
          )
          return rebuild if rebuild.err?

          Archive::ClaimResetter.delete_if_present(
            local_state_root: paths_result.value[:local_state], task_id: task_id
          )

          Result.ok(
            task_id: task_id.to_s,
            removed: true,
            deleted_path: task_dir.to_s
          )
        end

        # Strip the deleted id from every other live task's `blocked_by` so no
        # dangling dependency edge survives the delete (preferred over leaving
        # references that downstream readers must defensively ignore). Runs
        # before the index rebuild so the refreshed index reflects the cleanup.
        def clean_dangling_refs(tasks_root:, deleted_id:)
          dir = Pathname.new(tasks_root.to_s)
          return unless dir.directory?

          dir.children.each do |child|
            next unless child.directory? && IdGenerator.parse(child.basename.to_s)

            scrub_task_blocked_by(child.join(TaskReader::TASK_FILENAME), deleted_id)
          end
        end

        def scrub_task_blocked_by(task_yaml, deleted_id)
          return unless task_yaml.file?

          raw = YAML.safe_load(task_yaml.read, aliases: false, permitted_classes: [Time])
          return unless raw.is_a?(Hash)

          blocked_by = Array(raw['blocked_by'])
          return unless blocked_by.include?(deleted_id)

          raw['blocked_by'] = blocked_by - [deleted_id]
          AtomicYamlWriter.write(path: task_yaml, payload: raw)
        rescue Psych::SyntaxError
          nil
        end
      end
    end
  end
end
