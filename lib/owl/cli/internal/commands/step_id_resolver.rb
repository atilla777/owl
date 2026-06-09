# frozen_string_literal: true

require_relative '../../../result'
require_relative '../../../steps/internal/active_step_lock'
require_relative '../../../tasks/api'
require_relative '../../../tasks/internal/paths'
require_relative '../../../tasks/internal/task_reader'

module Owl
  module Cli
    module Internal
      module Commands
        # Resolves --task-id and --step-id for step CLI commands when the
        # caller (typically an orchestrator that already invoked `step start`
        # or `task claim`) wants to omit them. Priority for the task id:
        #
        #   1. explicit CLI flag
        #   2. the sole `.owl/local/active_steps/<TASK-ID>.yaml` lock, when
        #      exactly one task is mid-step (ambiguous if several → skip)
        #   3. the session's sole live task claim, when exactly one is held
        #   4. `.owl/local/current.yaml` (demoted single-session fallback)
        #
        # Step id then resolves from the explicit flag, that task's per-task
        # active-step lock, or a sole `running` step under the task.
        #
        # Each resolve_* returns a Result whose ok-value carries the resolved
        # id and a `source` discriminator (`explicit` | `active_step_lock` |
        # `live_claim` | `current_pointer` | `running_step_inference`) the
        # caller forwards to the success payload as observability.
        module StepIdResolver
          module_function

          def resolve_task_id(root:, explicit:)
            return Result.ok(task_id: explicit, source: 'explicit') if present?(explicit)

            lock = Owl::Steps::Internal::ActiveStepLock.load_sole(root: root)
            return lock if lock.err?
            if lock.value.is_a?(Hash) && present?(lock.value['task_id'])
              return Result.ok(task_id: lock.value['task_id'], source: 'active_step_lock')
            end

            resolve_task_id_from_claim_or_pointer(root: root)
          end

          # Falls back, in order, to the session's sole live claim and then
          # the demoted current pointer. Split out of resolve_task_id to keep
          # both methods under the AbcSize ceiling.
          def resolve_task_id_from_claim_or_pointer(root:)
            claim = sole_live_claim(root: root)
            return claim if claim&.err?
            if claim&.ok? && present?(claim.value[:task_id])
              return Result.ok(task_id: claim.value[:task_id], source: 'live_claim')
            end

            current = Owl::Tasks::Api.current(root: root)
            return current if current.err?

            Result.ok(task_id: current.value[:task_id], source: 'current_pointer')
          end

          # Returns Result.ok(task_id:) only when exactly one non-expired
          # claim exists; nil when zero or several (ambiguous → fall
          # through); the errored Result when the claims query itself fails.
          def sole_live_claim(root:)
            result = Owl::Tasks::Api.claims(root: root)
            return result if result.err?

            live = Array(result.value[:claims]).reject { |claim| claim[:expired] }
            return nil unless live.size == 1

            Result.ok(task_id: live.first[:task_id])
          end

          def resolve_step_id(root:, task_id:, explicit:, allow_running_inference:)
            return Result.ok(step_id: explicit, source: 'explicit') if present?(explicit)

            lock = Owl::Steps::Internal::ActiveStepLock.load(root: root, task_id: task_id)
            return lock if lock.err?
            if lock.value.is_a?(Hash) && lock.value['task_id'].to_s == task_id.to_s &&
               present?(lock.value['step_id'])
              return Result.ok(step_id: lock.value['step_id'], source: 'active_step_lock')
            end

            unless allow_running_inference
              return Result.err(
                code: :invalid_arguments,
                message: 'STEP-ID is required.'
              )
            end

            infer_running_step(root: root, task_id: task_id)
          end

          def infer_running_step(root:, task_id:)
            paths = Owl::Tasks::Internal::Paths.resolve(root: root)
            return paths if paths.err?

            task = Owl::Tasks::Internal::TaskReader.read(
              tasks_root: paths.value[:tasks], task_id: task_id
            )
            return task if task.err?

            steps = Array(task.value[:payload]['steps'] || task.value[:payload][:steps])
            running_ids = steps
                          .select { |s| s.is_a?(Hash) && (s['status'] || s[:status]).to_s == 'running' }
                          .map { |s| (s['id'] || s[:id]).to_s }

            return Result.ok(step_id: running_ids.first, source: 'running_step_inference') if running_ids.size == 1

            message = if running_ids.empty?
                        "No step in 'running' status for task '#{task_id}'."
                      else
                        "Multiple steps in 'running' status for task '#{task_id}'."
                      end
            Result.err(
              code: :ambiguous_step,
              message: message,
              details: { task_id: task_id.to_s, running_step_ids: running_ids },
              error_class: :recoverable
            )
          end

          def present?(value)
            value.is_a?(String) && !value.empty?
          end

          # Convenience for command `run` methods: resolves both ids and
          # mutates `options` in place with resolved values + source tags.
          # Returns the first errored Result or Result.ok(:resolved) on success.
          def apply!(root:, options:, allow_running_inference:)
            task = resolve_task_id(root: root, explicit: options[:task_id])
            return task if task.err?

            options[:task_id] = task.value[:task_id]
            options[:resolved_task_id_source] = task.value[:source]

            step = resolve_step_id(
              root: root, task_id: options[:task_id],
              explicit: options[:step_id], allow_running_inference: allow_running_inference
            )
            return step if step.err?

            options[:step_id] = step.value[:step_id]
            options[:resolved_step_id_source] = step.value[:source]
            Result.ok(:resolved)
          end
        end
      end
    end
  end
end
