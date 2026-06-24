# frozen_string_literal: true

require 'pathname'

require_relative '../../../config/api'
require_relative '../../../result'
require_relative '../../../storage/api'
require_relative '../../../workflows/api'
require_relative '../paths'
require_relative '../task_reader'
require_relative 'archived_task_writer'
require_relative 'claim_resetter'
require_relative 'completion_gate'
require_relative 'destination_planner'
require_relative 'mover'
require_relative 'slug_generator'

module Owl
  module Tasks
    module Internal
      module Archive
        module Orchestrator
          module_function

          def call(root:, task_id:, now:)
            context = load_context(root: root, task_id: task_id)
            return context if context.is_a?(Owl::Result::Err)

            completion_result = CompletionGate.call(
              workflow_body: context[:workflow_body], task_payload: context[:task_payload]
            )
            return completion_result if completion_result.err?

            call_single(root: root, task_id: task_id, context: context, now: now)
          end

          def call_single(root:, task_id:, context:, now:)
            plan_result = plan_destination(root: root, context: context, now: now)
            return plan_result if plan_result.is_a?(Owl::Result::Err)

            perform_single(root: root, task_id: task_id, context: context, plan: plan_result, now: now)
          end

          def load_context(root:, task_id:)
            paths_result = Owl::Tasks::Internal::Paths.resolve(root: root)
            return paths_result if paths_result.err?

            task_result = Owl::Tasks::Internal::TaskReader.read(
              tasks_root: paths_result.value[:tasks], task_id: task_id
            )
            return task_result if task_result.err?

            task_payload = task_result.value[:payload]
            if task_payload['status'].to_s == 'archived'
              return Result.err(
                code: :already_archived,
                message: "Task '#{task_id}' is already archived.",
                details: { task_id: task_id.to_s, archived_at: task_payload['archived_at'] }
              )
            end

            workflow_result = load_workflow(root: root, task_id: task_id, task_payload: task_payload)
            return workflow_result if workflow_result.is_a?(Owl::Result::Err)

            {
              paths: paths_result.value,
              task_id: task_id.to_s,
              task_payload: task_payload,
              workflow_key: workflow_result[:workflow_key],
              workflow_body: workflow_result[:workflow_body]
            }
          end

          def load_workflow(root:, task_id:, task_payload:)
            workflow_key = task_payload.dig('workflow', 'key')
            unless workflow_key
              return Result.err(
                code: :task_workflow_missing,
                message: "Task '#{task_id}' has no workflow key in task.yaml.",
                details: { task_id: task_id.to_s }
              )
            end

            workflow_result = Owl::Workflows::Api.find(root: root, key: workflow_key)
            return workflow_result if workflow_result.err?

            source = workflow_result.value[:source]
            unless source[:present]
              return Result.err(
                code: :workflow_source_missing,
                message: "Workflow source for '#{workflow_key}' is not present.",
                details: { key: workflow_key.to_s }
              )
            end

            { workflow_key: workflow_key,
              workflow_body: source[:body].is_a?(Hash) ? source[:body] : {} }
          end

          def plan_destination(root:, context:, now:)
            archive_root_result = resolve_archive_root(root: root)
            return archive_root_result if archive_root_result.err?

            slug = SlugGenerator.from(context[:task_payload]['title'])
            planner = DestinationPlanner.call(
              archive_root: archive_root_result.value,
              task_id: context[:task_id],
              slug: slug,
              now: now
            )
            return planner if planner.err?

            {
              slug: slug,
              destination_path: planner.value[:destination_path],
              collision_suffix: planner.value[:collision_suffix]
            }
          end

          def perform_single(root:, task_id:, context:, plan:, now:) # rubocop:disable Lint/UnusedMethodArgument
            archived_payload = ArchivedTaskWriter.build_payload(task_payload: context[:task_payload], now: now)
            source_dir = Pathname.new(context[:paths][:tasks].to_s) + context[:task_id]

            move = Mover.call(
              source_dir: source_dir,
              destination_path: plan[:destination_path],
              archived_payload: archived_payload,
              task_yaml_relative: Owl::Tasks::Internal::TaskReader::TASK_FILENAME,
              tasks_root: context[:paths][:tasks],
              index_path: context[:paths][:index],
              task_id: context[:task_id],
              root: root
            )
            return move if move.err?

            ClaimResetter.delete_if_present(
              local_state_root: context[:paths][:local_state], task_id: context[:task_id]
            )

            Result.ok(
              task_id: context[:task_id],
              workflow_key: context[:workflow_key].to_s,
              from: source_dir.to_s,
              to: plan[:destination_path].to_s,
              slug: plan[:slug],
              collision_suffix: plan[:collision_suffix],
              archived_at: archived_payload['archived_at'],
              current_reset: move.value[:current_reset]
            )
          end

          def resolve_archive_root(root:)
            config_result = Owl::Config::Api.load(root: root)
            return config_result if config_result.err?

            profile = config_result.value.active_profile
            Owl::Storage::Api.resolve(role: 'archive', profile: profile, root: root)
          end
        end
      end
    end
  end
end
