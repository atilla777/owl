# frozen_string_literal: true

require 'optparse'

require_relative '../../../steps/api'
require_relative '../json_printer'
require_relative 'step_id_resolver'
require_relative 'task_support'

module Owl
  module Cli
    module Internal
      module Commands
        module StepReset
          module_function

          def run(argv:, stdout:, stderr:, cwd:, env: ENV.to_h) # rubocop:disable Lint/UnusedMethodArgument
            options = parse_options(argv)

            root = TaskSupport.resolve_root(options[:root], cwd, stderr: stderr)
            return root if root.is_a?(Integer)

            resolution = StepIdResolver.apply!(root: root, options: options, allow_running_inference: true)
            return JsonPrinter.failure(stderr, **TaskSupport.error_payload(resolution)) if resolution.err?

            result = Owl::Steps::Api.reset(
              root: root,
              task_id: options[:task_id],
              step_id: options[:step_id]
            )
            if result.err?
              return recover_or_fail(
                root: root, options: options, result: result, stdout: stdout, stderr: stderr
              )
            end

            clear_active_step_lock(root: root, options: options)

            payload = {
              ok: true,
              task_id: options[:task_id],
              step: result.value[:step],
              resolved_task_id_source: options[:resolved_task_id_source],
              resolved_step_id_source: options[:resolved_step_id_source]
            }
            paths = Owl::Steps::Api.local_paths(root: root, task_id: options[:task_id])
            payload[:task_path] = paths.value[:task_file].task_path if paths.ok?
            JsonPrinter.success(stdout, payload)
          rescue OptionParser::ParseError => e
            JsonPrinter.failure(stderr, code: :invalid_arguments, message: e.message)
          end

          # When `Steps::Api.reset` rejects a non-running step with
          # `step_not_running`, the step may still be holding a stale active-step
          # lock (e.g. a `skip`/`abandon` from before this behaviour existed, or
          # a crash). Recover by clearing that stale lock and returning success —
          # the step status is left unchanged (nothing to roll back), only the
          # orphaned lock is released, so the operator avoids `step start --force`.
          # Strict guard: recovery fires only on `step_not_running` AND a matching
          # lock present; otherwise the original error is returned unchanged so
          # genuine "nothing to reset" cases stay visible.
          def recover_or_fail(root:, options:, result:, stdout:, stderr:)
            unless result.code == :step_not_running
              return JsonPrinter.failure(stderr, **TaskSupport.error_payload(result))
            end

            lock = Owl::Steps::Api.active_step_lock_load(root: root, task_id: options[:task_id])
            matching = lock.ok? && lock.value && Owl::Steps::Api.active_step_lock_matches?(
              lock.value, task_id: options[:task_id], step_id: options[:step_id]
            )
            return JsonPrinter.failure(stderr, **TaskSupport.error_payload(result)) unless matching

            Owl::Steps::Api.active_step_lock_clear(root: root, task_id: options[:task_id])
            emit_recovery(root: root, options: options, result: result, stdout: stdout)
          end

          def emit_recovery(root:, options:, result:, stdout:)
            payload = {
              ok: true,
              task_id: options[:task_id],
              recovered_stale_lock: true,
              step_status: result.details[:current_status],
              resolved_task_id_source: options[:resolved_task_id_source],
              resolved_step_id_source: options[:resolved_step_id_source]
            }
            paths = Owl::Steps::Api.local_paths(root: root, task_id: options[:task_id])
            payload[:task_path] = paths.value[:task_file].task_path if paths.ok?
            JsonPrinter.success(stdout, payload)
          end

          # Release the per-task active-step lock so the reset task is free for
          # the next `step start`/`step complete`. Mirrors `step complete`, which
          # clears the lock after a successful state change. Only clears when the
          # lock refers to the step just reset, so a lock for a different step is
          # left untouched; a no-op when no lock exists.
          def clear_active_step_lock(root:, options:)
            lock = Owl::Steps::Api.active_step_lock_load(root: root, task_id: options[:task_id])
            return unless lock.ok? && lock.value
            return unless Owl::Steps::Api.active_step_lock_matches?(
              lock.value, task_id: options[:task_id], step_id: options[:step_id]
            )

            Owl::Steps::Api.active_step_lock_clear(root: root, task_id: options[:task_id])
          end

          def parse_options(argv)
            options = { root: nil, task_id: nil, step_id: nil }
            parser = OptionParser.new do |opts|
              opts.banner = 'Usage: owl step reset TASK-ID STEP-ID [--root PATH] [--json]'
              opts.on('--root PATH', String) { |v| options[:root] = v }
              opts.on('--json', 'Force JSON output (default)') { options[:json] = true }
            end
            positional = parser.parse(argv)
            options[:task_id] = positional[0]
            options[:step_id] = positional[1]
            options
          end
        end
      end
    end
  end
end
