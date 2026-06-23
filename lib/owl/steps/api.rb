# frozen_string_literal: true

require_relative '../result'
require_relative '../tasks/api'
require_relative '../tasks/internal/paths'
require_relative '../tasks/internal/task_reader'
require_relative '../verification/api'
require_relative '../workflows/api'
require_relative '../workflows/internal/graph_builder'
require_relative 'internal/archive_finalizer'
require_relative 'internal/artifact_sha_collector'
require_relative 'internal/bundle_builder'
require_relative 'internal/invocation_builder'
require_relative 'internal/output_validator'
require_relative 'internal/statuses'
require_relative 'internal/status_writer'

module Owl
  module Steps
    module Api # rubocop:disable Metrics/ModuleLength
      # Keys that filesystem-backend payloads expose as transitional path
      # carriers. They are stripped from the public DTO so backends without a
      # local filesystem view can satisfy the same contract.
      STRIPPED_PATH_KEYS = %i[path local].freeze

      module_function

      def invocation(root:, task_id:, step_id:)
        Internal::InvocationBuilder.call(root: root, task_id: task_id, step_id: step_id)
      end

      def show(root:, task_id:, step_id:)
        Internal::BundleBuilder.call(root: root, task_id: task_id, step_id: step_id)
      end

      def start(root:, task_id:, step_id:, variant: nil)
        paths = Owl::Tasks::Internal::Paths.resolve(root: root)
        return paths if paths.err?

        if variant
          set_result = Owl::Tasks::Api.set_step_variant(
            root: root, task_id: task_id, step_id: step_id, variant: variant
          )
          return set_result if set_result.err?
        end

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

        strip_local(Internal::StatusWriter.update(
                      tasks_root: paths.value[:tasks],
                      task_id: task_id,
                      step_id: step_id,
                      attributes: { 'status' => 'running' }
                    ))
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
          # Re-completing a `done` step is an idempotent no-op (no task.yaml
          # rewrite), so `commit_push` can self-complete before it commits and
          # the orchestrator's safety-net re-complete stays harmless.
          return idempotent_complete(paths.value, task_id, step_id) if current == 'done'

          return Result.err(
            code: :step_not_running,
            message: "Step '#{step_id}' is not running (current status: #{current}).",
            details: { task_id: task_id, step_id: step_id, current_status: current }
          )
        end

        # The objective verification gate runs BEFORE output validation: for a
        # `verify: true` step it executes the configured command and (re)writes
        # the `verification` artifact, so OutputValidator then validates an
        # Owl-authored, fresh-by-construction result. A failed gate keeps the
        # step `running`.
        gate = Owl::Verification::Api.gate(root: root, task_id: task_id, step_id: step_id)
        return gate if gate.err?

        validation = Internal::OutputValidator.call(root: root, task_id: task_id, step_id: step_id)
        return validation if validation.err?

        attributes = { 'status' => 'done' }
        sha_result = Internal::ArtifactShaCollector.call(root: root, task_id: task_id, step_id: step_id)
        attributes['content_sha'] = sha_result.value if sha_result.ok? && !sha_result.value.nil?

        write = strip_local(Internal::StatusWriter.update(
                              tasks_root: paths.value[:tasks],
                              task_id: task_id,
                              step_id: step_id,
                              attributes: attributes
                            ))
        return write if write.err?

        Internal::ArchiveFinalizer.call(
          tasks_root: paths.value[:tasks], local_state_root: paths.value[:local_state], task_id: task_id
        )
        with_gate_warnings(write, gate)
      end

      # Surface non-blocking gate warnings (inactive gate / partial status) to
      # the caller so the CLI can print them to stderr without failing.
      def with_gate_warnings(write, gate)
        warning = gate.value[:warning] if gate.ok? && gate.value.is_a?(Hash)
        return write unless warning

        Result.ok(write.value.merge(warnings: [warning]))
      end

      def reopen(root:, task_id:, step_id:, cascade: false)
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

        unless current == 'done'
          return Result.err(
            code: :step_not_completed,
            message: "Step '#{step_id}' is not done (current status: #{current}).",
            details: { task_id: task_id, step_id: step_id, current_status: current }
          )
        end

        missing = missing_artifact_for(root: root, task_id: task_id, step_id: step_id)
        return missing if missing.is_a?(Owl::Result::Err)

        targets_result = reopen_targets(root: root, task_id: task_id, step_id: step_id, cascade: cascade)
        return targets_result if targets_result.is_a?(Owl::Result::Err)

        reopened = []
        targets_result.each do |target_id|
          target_status = current_status(paths.value[:tasks], task_id, target_id)
          next unless target_status == 'done'

          write_result = Internal::StatusWriter.update(
            tasks_root: paths.value[:tasks],
            task_id: task_id,
            step_id: target_id,
            attributes: { 'status' => Internal::Statuses::DEFAULT }
          )
          return write_result if write_result.err?

          reopened << target_id
        end

        Result.ok(task_id: task_id.to_s, reopened: reopened)
      end

      def missing_artifact_for(root:, task_id:, step_id:)
        creates = Internal::ArtifactShaCollector.creates_for(root: root, task_id: task_id, step_id: step_id)
        return creates if creates.is_a?(Owl::Result::Err)

        creates.each do |key|
          descriptor = Owl::Artifacts::Internal::TaskArtifactResolver.call(
            root: root, task_id: task_id, artifact_key: key
          )
          return descriptor if descriptor.err?
          next if descriptor.value[:multiple]
          next if descriptor.value[:exists]

          return Result.err(
            code: :artifact_missing,
            message: "Artifact '#{key}' is missing on disk for task '#{task_id}'.",
            details: { task_id: task_id.to_s, step_id: step_id.to_s, artifact_key: key.to_s }
          )
        end

        nil
      end

      def reopen_targets(root:, task_id:, step_id:, cascade:)
        return [step_id.to_s] unless cascade

        task = Owl::Tasks::Api.inspect(root: root, task_id: task_id)
        return task if task.err?

        workflow_key = task.value[:payload].dig('workflow', 'key')
        unless workflow_key
          return Result.err(
            code: :task_workflow_missing,
            message: "Task '#{task_id}' has no workflow key in task.yaml.",
            details: { task_id: task_id.to_s }
          )
        end

        definition = Owl::Workflows::Api.definition(root: root, workflow_key: workflow_key)
        return definition if definition.err?

        nodes = definition.value[:graph][:nodes]
        downstream = Owl::Workflows::Internal::GraphBuilder.downstream_closure(nodes, step_id.to_s)
        [step_id.to_s] + downstream
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

        strip_local(Internal::StatusWriter.update(
                      tasks_root: paths.value[:tasks],
                      task_id: task_id,
                      step_id: step_id,
                      attributes: { 'status' => 'skipped', 'skip_reason' => reason_text }
                    ))
      end

      def reset(root:, task_id:, step_id:)
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

        strip_local(Internal::StatusWriter.update(
                      tasks_root: paths.value[:tasks],
                      task_id: task_id,
                      step_id: step_id,
                      attributes: { 'status' => Internal::Statuses::DEFAULT }
                    ))
      end

      def local_paths(root:, task_id:)
        Owl::Tasks::Api.local_paths(root: root, task_id: task_id)
      end

      def strip_local(result)
        return result if result.err?
        return result unless result.value.is_a?(Hash)

        Owl::Result.ok(result.value.except(*STRIPPED_PATH_KEYS))
      end

      def current_status(tasks_root, task_id, step_id)
        read = Owl::Tasks::Internal::TaskReader.read(tasks_root: tasks_root, task_id: task_id)
        return nil if read.err?

        steps = read.value[:payload]['steps'] || read.value[:payload][:steps] || []
        step = steps.find { |s| s.is_a?(Hash) && (s['id'] || s[:id]).to_s == step_id.to_s }
        step && (step['status'] || step[:status] || Internal::Statuses::DEFAULT).to_s
      end

      # Release the archive pointer if the workflow is terminal, then report
      # success without touching task.yaml.
      def idempotent_complete(paths, task_id, step_id)
        Internal::ArchiveFinalizer.call(
          tasks_root: paths[:tasks], local_state_root: paths[:local_state], task_id: task_id
        )
        Result.ok(step: { 'id' => step_id.to_s, 'status' => 'done' }, already_done: true)
      end

      private_class_method :strip_local
    end
  end
end
