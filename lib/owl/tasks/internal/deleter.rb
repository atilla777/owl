# frozen_string_literal: true

require 'fileutils'
require 'pathname'

require_relative '../../result'
require_relative 'archive/claim_resetter'
require_relative 'index_rebuilder'
require_relative 'paths'

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

          rebuild = IndexRebuilder.rebuild(
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
      end
    end
  end
end
