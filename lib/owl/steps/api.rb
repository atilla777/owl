# frozen_string_literal: true

require_relative '../result'
require_relative '../tasks/internal/paths'
require_relative '../tasks/internal/task_reader'
require_relative '../workflows/api'
require_relative 'internal/bundle_builder'
require_relative 'internal/invocation_builder'
require_relative 'internal/output_validator'
require_relative 'internal/statuses'
require_relative 'internal/status_writer'

module Owl
  module Steps
    module Api
      module_function

      def invocation(root:, task_id:, step_id:)
        Internal::InvocationBuilder.call(root: root, task_id: task_id, step_id: step_id)
      end

      def show(root:, task_id:, step_id:)
        Internal::BundleBuilder.call(root: root, task_id: task_id, step_id: step_id)
      end

      def start(root:, task_id:, step_id:)
        paths = Owl::Tasks::Internal::Paths.resolve(root: root)
        return paths if paths.err?

        ready_result = Owl::Workflows::Api.ready_steps(root: root, task_id: task_id)
        return ready_result if ready_result.err?

        ready_ids = ready_result.value[:ready].map { |s| s[:id] }
        unless ready_ids.include?(step_id.to_s)
          current = current_status(paths.value[:tasks], task_id, step_id)
          return Result.err(
            code: :step_not_ready,
            message: "Step '#{step_id}' is not in the ready set for task '#{task_id}'.",
            details: { task_id: task_id, step_id: step_id, current_status: current, ready_steps: ready_ids }
          )
        end

        Internal::StatusWriter.update(
          tasks_root: paths.value[:tasks],
          task_id: task_id,
          step_id: step_id,
          attributes: { 'status' => 'running' }
        )
      end

      def complete(root:, task_id:, step_id:)
        paths = Owl::Tasks::Internal::Paths.resolve(root: root)
        return paths if paths.err?

        current = current_status(paths.value[:tasks], task_id, step_id)
        if current.nil?
          return Result.err(
            code: :unknown_step_id,
            message: "Step '#{step_id}' is not defined for task '#{task_id}'.",
            details: { task_id: task_id, step_id: step_id }
          )
        end

        unless current == 'running'
          return Result.err(
            code: :step_not_running,
            message: "Step '#{step_id}' is not running (current status: #{current}).",
            details: { task_id: task_id, step_id: step_id, current_status: current }
          )
        end

        validation = Internal::OutputValidator.call(root: root, task_id: task_id, step_id: step_id)
        return validation if validation.err?

        Internal::StatusWriter.update(
          tasks_root: paths.value[:tasks],
          task_id: task_id,
          step_id: step_id,
          attributes: { 'status' => 'done' }
        )
      end

      def skip(root:, task_id:, step_id:, reason:)
        reason_text = reason.to_s.strip
        if reason_text.empty?
          return Result.err(
            code: :missing_reason,
            message: 'Skip requires a non-empty --reason.',
            details: { task_id: task_id, step_id: step_id }
          )
        end

        paths = Owl::Tasks::Internal::Paths.resolve(root: root)
        return paths if paths.err?

        current = current_status(paths.value[:tasks], task_id, step_id)
        if current.nil?
          return Result.err(
            code: :unknown_step_id,
            message: "Step '#{step_id}' is not defined for task '#{task_id}'.",
            details: { task_id: task_id, step_id: step_id }
          )
        end

        if current == 'done'
          return Result.err(
            code: :step_already_done,
            message: "Step '#{step_id}' is already done and cannot be skipped.",
            details: { task_id: task_id, step_id: step_id, current_status: current }
          )
        end

        Internal::StatusWriter.update(
          tasks_root: paths.value[:tasks],
          task_id: task_id,
          step_id: step_id,
          attributes: { 'status' => 'skipped', 'skip_reason' => reason_text }
        )
      end

      def current_status(tasks_root, task_id, step_id)
        read = Owl::Tasks::Internal::TaskReader.read(tasks_root: tasks_root, task_id: task_id)
        return nil if read.err?

        steps = read.value[:payload]['steps'] || read.value[:payload][:steps] || []
        step = steps.find { |s| s.is_a?(Hash) && (s['id'] || s[:id]).to_s == step_id.to_s }
        return nil unless step

        (step['status'] || step[:status] || Internal::Statuses::DEFAULT).to_s
      end
    end
  end
end
