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
        module StepSkip
          module_function

          def run(argv:, stdout:, stderr:, cwd:, env: ENV.to_h) # rubocop:disable Lint/UnusedMethodArgument
            options = parse_options(argv)

            root = TaskSupport.resolve_root(options[:root], cwd, stderr: stderr)
            return root if root.is_a?(Integer)

            resolution = StepIdResolver.apply!(root: root, options: options, allow_running_inference: true)
            return JsonPrinter.failure(stderr, **TaskSupport.error_payload(resolution)) if resolution.err?

            result = Owl::Steps::Api.skip(
              root: root,
              task_id: options[:task_id],
              step_id: options[:step_id],
              reason: options[:reason]
            )
            return JsonPrinter.failure(stderr, **TaskSupport.error_payload(result)) if result.err?

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

          # Release the per-task active-step lock when skipping the step that
          # holds it. Mirrors `step reset`/`step complete`, which clear the lock
          # after a successful state change. Match-scoped: only clears when the
          # lock refers to the step just skipped, so a lock for a different step
          # is left untouched; a no-op when no lock exists.
          def clear_active_step_lock(root:, options:)
            lock = Owl::Steps::Api.active_step_lock_load(root: root, task_id: options[:task_id])
            return unless lock.ok? && lock.value
            return unless Owl::Steps::Api.active_step_lock_matches?(
              lock.value, task_id: options[:task_id], step_id: options[:step_id]
            )

            Owl::Steps::Api.active_step_lock_clear(root: root, task_id: options[:task_id])
          end

          def parse_options(argv)
            options = { root: nil, task_id: nil, step_id: nil, reason: nil }
            parser = OptionParser.new do |opts|
              opts.banner = 'Usage: owl step skip TASK-ID STEP-ID --reason TEXT [--root PATH] [--json]'
              opts.on('--reason TEXT', String) { |v| options[:reason] = v }
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
