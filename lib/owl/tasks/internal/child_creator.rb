# frozen_string_literal: true

require 'pathname'

require_relative '../../result'
require_relative '../../artifacts/api'
require_relative '../../steps/internal/artifact_sha_collector'
require_relative '../../steps/internal/status_writer'
require_relative '../../storage/api'
require_relative 'allowed_children_guard'
require_relative 'paths'
require_relative 'task_reader'

module Owl
  module Tasks
    module Internal
      module ChildCreator
        COMPOSITE_KIND = 'composite_task'
        MAX_PARENT_CHAIN = 32
        BRIEF_STEP_ID = 'brief'
        BRIEF_ARTIFACT_KEY = 'brief'

        module_function

        def call(root:, parent_id:, workflow:, title:, creator:, brief_body: nil)
          paths_result = Paths.resolve(root: root)
          return paths_result if paths_result.err?

          tasks_root = paths_result.value[:tasks]
          parent_payload = read_parent(tasks_root: tasks_root, parent_id: parent_id)
          return parent_payload if parent_payload.is_a?(Result::Err)

          chain_check = walk_parent_chain(tasks_root: tasks_root, start_id: parent_id)
          return chain_check if chain_check.is_a?(Result::Err)

          guard = AllowedChildrenGuard.call(
            root: root,
            parent_id: parent_id,
            parent_workflow_key: parent_payload.dig('workflow', 'key'),
            child_workflow_key: workflow
          )
          return guard if guard.err?

          create_result = creator.call(
            root: root,
            workflow: workflow,
            title: title,
            parent_id: parent_id.to_s
          )
          return create_result if create_result.err?

          return create_result if brief_body.nil?

          seed_result = seed_brief(
            root: root,
            tasks_root: tasks_root,
            task_id: create_result.value[:task_id],
            brief_body: brief_body
          )
          return seed_result if seed_result.is_a?(Result::Err)

          create_result
        end

        def seed_brief(root:, tasks_root:, task_id:, brief_body:)
          descriptor = Owl::Artifacts::Api.resolve(
            root: root, task_id: task_id, artifact_key: BRIEF_ARTIFACT_KEY
          )
          return descriptor if descriptor.err?

          path = Pathname.new(descriptor.value[:path])
          path.dirname.mkpath
          write_result = Owl::Storage::Api.write(path: path, contents: brief_body.to_s)
          return write_result if write_result.err?

          # Record content_sha so drift detection works for pre-authored briefs,
          # matching what `owl step complete` does for normally-completed steps.
          attributes = { 'status' => 'done' }
          sha_result = Owl::Steps::Internal::ArtifactShaCollector.call(
            root: root, task_id: task_id, step_id: BRIEF_STEP_ID
          )
          attributes['content_sha'] = sha_result.value if sha_result.ok? && !sha_result.value.nil?

          Owl::Steps::Internal::StatusWriter.update(
            tasks_root: tasks_root,
            task_id: task_id,
            step_id: BRIEF_STEP_ID,
            attributes: attributes
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
