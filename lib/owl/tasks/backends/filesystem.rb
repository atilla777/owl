# frozen_string_literal: true

require_relative '../../result'
require_relative '../backend'
require_relative '../local'
require_relative '../internal/aggregate_status'
require_relative '../internal/archive/orchestrator'
require_relative '../internal/child_creator'
require_relative '../internal/children_lister'
require_relative '../internal/current_pointer'
require_relative '../internal/id_generator'
require_relative '../internal/index_reader'
require_relative '../internal/index_rebuilder'
require_relative '../internal/parent_resolver'
require_relative '../internal/paths'
require_relative '../internal/task_reader'
require_relative '../internal/task_writer'
require_relative '../internal/tree_builder'
require_relative '../internal/workflow_snapshot'

module Owl
  module Tasks
    module Backends
      class Filesystem # rubocop:disable Metrics/ClassLength
        include Owl::Tasks::Backend

        def initialize(root:)
          @root = root
        end

        def list
          paths_result = Internal::Paths.resolve(root: @root)
          return paths_result if paths_result.err?

          index_result = Internal::IndexReader.read(index_path: paths_result.value[:index])
          return index_result if index_result.err?

          Result.ok(
            index_path: paths_result.value[:index].to_s,
            schema_version: index_result.value[:schema_version],
            tasks: index_result.value[:tasks],
            local: { index: Owl::Tasks::Local::Index.new(index_path: paths_result.value[:index].to_s) }
          )
        end

        def inspect_task(task_id:)
          paths_result = Internal::Paths.resolve(root: @root)
          return paths_result if paths_result.err?

          read = Internal::TaskReader.read(tasks_root: paths_result.value[:tasks], task_id: task_id)
          return read if read.err?

          Result.ok(read.value.merge(
                      local: { task_file: Owl::Tasks::Local::TaskFile.new(task_path: read.value[:path]) }
                    ))
        end

        def create(workflow:, title:, parent_id: nil, kind: nil, step_variants: nil)
          paths_result = Internal::Paths.resolve(root: @root)
          return paths_result if paths_result.err?

          snapshot_result = Internal::WorkflowSnapshot.snapshot(root: @root, workflow_key: workflow)
          return snapshot_result if snapshot_result.err?

          variant_validation = validate_step_variants(snapshot_result.value, step_variants)
          return variant_validation if variant_validation&.err?

          paths = paths_result.value
          task_id = Internal::IdGenerator.next_id(
            tasks_root: paths[:tasks],
            index_path: paths[:index]
          )

          payload = Internal::TaskWriter.build_payload(
            task_id: task_id,
            title: title.to_s,
            parent_id: parent_id,
            kind: kind,
            step_variants: step_variants,
            snapshot: snapshot_result.value
          )
          task_path = Internal::TaskWriter.write(
            tasks_root: paths[:tasks],
            task_id: task_id,
            payload: payload
          )

          rebuild_result = Internal::IndexRebuilder.rebuild(
            tasks_root: paths[:tasks],
            index_path: paths[:index]
          )
          return rebuild_result if rebuild_result.err?

          Result.ok(
            task_id: task_id,
            task_path: task_path.to_s,
            payload: payload,
            index_path: rebuild_result.value[:index_path],
            local: {
              task_file: Owl::Tasks::Local::TaskFile.new(task_path: task_path.to_s),
              index: Owl::Tasks::Local::Index.new(index_path: rebuild_result.value[:index_path])
            }
          )
        end

        def set_step_variant(task_id:, step_id:, variant:)
          paths_result = Internal::Paths.resolve(root: @root)
          return paths_result if paths_result.err?

          tasks_root = paths_result.value[:tasks]
          read = Internal::TaskReader.read(tasks_root: tasks_root, task_id: task_id)
          return read if read.err?

          payload = read.value[:payload]
          variant_check = validate_variant_against_workflow(
            payload: payload,
            step_id: step_id,
            variant: variant
          )
          return variant_check if variant_check&.err?

          payload['step_variants'] ||= {}
          payload['step_variants'][step_id.to_s] = variant.to_s

          Internal::TaskWriter.write(
            tasks_root: tasks_root,
            task_id: task_id,
            payload: payload
          )

          Result.ok(
            task_id: task_id.to_s,
            step_id: step_id.to_s,
            variant: variant.to_s,
            step_variants: payload['step_variants']
          )
        end

        def archive_task(task_id:, now: Time.now.utc)
          Internal::Archive::Orchestrator.call(root: @root, task_id: task_id, now: now)
        end

        def children(parent_id:)
          Internal::ChildrenLister.call(root: @root, parent_id: parent_id)
        end

        def parent(task_id:)
          Internal::ParentResolver.call(root: @root, task_id: task_id)
        end

        def tree
          Internal::TreeBuilder.call(root: @root)
        end

        def aggregate_status(task_id:)
          Internal::AggregateStatus.call(root: @root, task_id: task_id)
        end

        def current
          paths_result = Internal::Paths.resolve(root: @root)
          return paths_result if paths_result.err?

          pointer_result = Internal::CurrentPointer.read(local_state_root: paths_result.value[:local_state])
          return pointer_result if pointer_result.err?

          task_id = pointer_result.value[:task_id]
          read_result = Internal::TaskReader.read(
            tasks_root: paths_result.value[:tasks],
            task_id: task_id
          )
          return read_result if read_result.err?

          Result.ok(
            task_id: task_id,
            set_at: pointer_result.value[:set_at],
            pointer_path: pointer_result.value[:path],
            payload: read_result.value[:payload],
            task_path: read_result.value[:path],
            local: {
              task_file: Owl::Tasks::Local::TaskFile.new(task_path: read_result.value[:path]),
              pointer: Owl::Tasks::Local::Pointer.new(pointer_path: pointer_result.value[:path])
            }
          )
        end

        def use(task_id:)
          paths_result = Internal::Paths.resolve(root: @root)
          return paths_result if paths_result.err?

          read_result = Internal::TaskReader.read(
            tasks_root: paths_result.value[:tasks],
            task_id: task_id
          )
          return read_result if read_result.err?

          write_result = Internal::CurrentPointer.write(
            local_state_root: paths_result.value[:local_state],
            task_id: task_id
          )
          return write_result if write_result.err?

          Result.ok(write_result.value.merge(
                      local: { pointer: Owl::Tasks::Local::Pointer.new(pointer_path: write_result.value[:path]) }
                    ))
        end

        def rebuild_index
          paths_result = Internal::Paths.resolve(root: @root)
          return paths_result if paths_result.err?

          rebuild_result = Internal::IndexRebuilder.rebuild(
            tasks_root: paths_result.value[:tasks],
            index_path: paths_result.value[:index]
          )
          return rebuild_result if rebuild_result.err?

          Result.ok(rebuild_result.value.merge(
                      local: { index: Owl::Tasks::Local::Index.new(index_path: rebuild_result.value[:index_path]) }
                    ))
        end

        def child_create(parent_id:, workflow:, title:, brief_body: nil)
          Internal::ChildCreator.call(
            root: @root,
            parent_id: parent_id,
            workflow: workflow,
            title: title,
            creator: method(:create_via_self),
            brief_body: brief_body
          )
        end

        def local_paths_for(task_id: nil)
          paths_result = Internal::Paths.resolve(root: @root)
          return paths_result if paths_result.err?

          paths = paths_result.value
          if task_id.nil?
            Result.ok(
              index: Owl::Tasks::Local::Index.new(index_path: paths[:index].to_s),
              pointer: Owl::Tasks::Local::Pointer.new(
                pointer_path: Internal::CurrentPointer.pointer_path(local_state_root: paths[:local_state]).to_s
              )
            )
          else
            task_path = Internal::TaskReader.task_yaml_path(tasks_root: paths[:tasks], task_id: task_id)
            Result.ok(
              task_file: Owl::Tasks::Local::TaskFile.new(task_path: task_path.to_s),
              index: Owl::Tasks::Local::Index.new(index_path: paths[:index].to_s),
              pointer: Owl::Tasks::Local::Pointer.new(
                pointer_path: Internal::CurrentPointer.pointer_path(local_state_root: paths[:local_state]).to_s
              )
            )
          end
        end

        private

        def create_via_self(root:, workflow:, title:, parent_id: nil, kind: nil)
          _ = root
          create(workflow: workflow, title: title, parent_id: parent_id, kind: kind)
        end

        def validate_step_variants(snapshot, raw)
          return nil unless raw.is_a?(Hash) && !raw.empty?

          steps_by_id = Array(snapshot[:steps]).each_with_object({}) do |step, acc|
            next unless step.is_a?(Hash)

            id = (step['id'] || step[:id]).to_s
            acc[id] = step unless id.empty?
          end

          raw.each do |step_id, variant|
            err = check_variant_against_step(steps_by_id[step_id.to_s], step_id, variant)
            return err if err
          end
          nil
        end

        def validate_variant_against_workflow(payload:, step_id:, variant:)
          workflow_key = payload.dig('workflow', 'key')
          return unknown_workflow_error(workflow_key) unless workflow_key

          lookup = Owl::Workflows::Api.find(root: @root, key: workflow_key)
          return lookup if lookup.err?

          source = lookup.value[:source]
          body = source.is_a?(Hash) ? (source[:body] || source['body']) : nil
          steps = body.is_a?(Hash) ? Array(body['steps'] || body[:steps]) : []
          step = steps.find { |s| s.is_a?(Hash) && (s['id'] || s[:id]).to_s == step_id.to_s }

          check_variant_against_step(step, step_id, variant)
        end

        def check_variant_against_step(step, step_id, variant)
          return unknown_step_error(step_id) if step.nil?

          variants = step['variants'] || step[:variants]
          return step_without_variants_error(step_id) unless variants.is_a?(Hash) && !variants.empty?

          variant_str = variant.to_s
          return nil if variants.key?(variant_str)

          Result.err(
            code: :unknown_step_variant,
            message: "Step '#{step_id}' has no variant '#{variant_str}' " \
                     "(available: #{variants.keys.sort.inspect}).",
            details: { step_id: step_id.to_s, variant: variant_str, available: variants.keys.sort }
          )
        end

        def unknown_step_error(step_id)
          Result.err(
            code: :unknown_step_id,
            message: "Step '#{step_id}' is not defined in this workflow.",
            details: { step_id: step_id.to_s }
          )
        end

        def step_without_variants_error(step_id)
          Result.err(
            code: :step_without_variants,
            message: "Step '#{step_id}' does not declare a `variants:` block.",
            details: { step_id: step_id.to_s }
          )
        end

        def unknown_workflow_error(workflow_key)
          Result.err(
            code: :task_workflow_missing,
            message: 'Task workflow.key is missing; cannot validate step variant.',
            details: { workflow_key: workflow_key }
          )
        end
      end
    end
  end
end
