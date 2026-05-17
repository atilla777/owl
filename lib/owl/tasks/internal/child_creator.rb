# frozen_string_literal: true

require_relative '../../result'
require_relative 'paths'
require_relative 'task_reader'

module Owl
  module Tasks
    module Internal
      module ChildCreator
        COMPOSITE_KIND = 'composite_task'
        MAX_PARENT_CHAIN = 32

        module_function

        def call(root:, parent_id:, workflow:, title:, creator:)
          paths_result = Paths.resolve(root: root)
          return paths_result if paths_result.err?

          tasks_root = paths_result.value[:tasks]
          parent_payload = read_parent(tasks_root: tasks_root, parent_id: parent_id)
          return parent_payload if parent_payload.is_a?(Result::Err)

          chain_check = walk_parent_chain(tasks_root: tasks_root, start_id: parent_id)
          return chain_check if chain_check.is_a?(Result::Err)

          creator.call(
            root: root,
            workflow: workflow,
            title: title,
            parent_id: parent_id.to_s
          )
        end

        def read_parent(tasks_root:, parent_id:)
          result = TaskReader.read(tasks_root: tasks_root, task_id: parent_id)
          return result if result.err?

          payload = result.value[:payload]
          unless payload['kind'].to_s == COMPOSITE_KIND
            return Result.err(
              code: :parent_not_composite,
              message: "Parent task '#{parent_id}' is not a composite_task (kind=#{payload['kind'].inspect}).",
              details: { parent_id: parent_id.to_s, kind: payload['kind'] }
            )
          end

          payload
        end

        def walk_parent_chain(tasks_root:, start_id:)
          seen = []
          current_id = start_id.to_s
          MAX_PARENT_CHAIN.times do
            return Result.ok(safe: true) if current_id.empty?

            if seen.include?(current_id)
              return Result.err(
                code: :parent_chain_cycle,
                message: "Parent chain forms a cycle at task '#{current_id}'.",
                details: { cycle_at: current_id, chain: seen }
              )
            end

            seen << current_id
            read = TaskReader.read(tasks_root: tasks_root, task_id: current_id)
            return read if read.err?

            current_id = read.value[:payload]['parent_id'].to_s
          end

          Result.err(
            code: :parent_chain_too_deep,
            message: "Parent chain exceeds MAX_PARENT_CHAIN=#{MAX_PARENT_CHAIN}.",
            details: { chain: seen }
          )
        end
      end
    end
  end
end
