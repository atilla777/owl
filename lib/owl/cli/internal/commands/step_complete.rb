# frozen_string_literal: true

require 'json'
require 'optparse'

require_relative '../../../steps/api'
require_relative '../../../steps/internal/active_step_lock'
require_relative '../../../steps/internal/drift_detector'
require_relative '../../../steps/internal/drift_policy'
require_relative '../json_printer'
require_relative 'drift_warning_printer'
require_relative 'step_id_resolver'
require_relative 'task_support'

module Owl
  module Cli
    module Internal
      module Commands
        module StepComplete
          module_function

          def run(argv:, stdout:, stderr:, cwd:, env: ENV.to_h) # rubocop:disable Lint/UnusedMethodArgument
            options = parse_options(argv)

            root = TaskSupport.resolve_root(options[:root], cwd, stderr: stderr)
            return root if root.is_a?(Integer)

            resolution = StepIdResolver.apply!(root: root, options: options, allow_running_inference: true)
            return JsonPrinter.failure(stderr, **TaskSupport.error_payload(resolution)) if resolution.err?

            drift_block = handle_drift(root: root, options: options, stderr: stderr)
            return drift_block if drift_block

            mismatch = lock_mismatch_response(root: root, options: options, stderr: stderr)
            return mismatch if mismatch

            result = Owl::Steps::Api.complete(
              root: root, task_id: options[:task_id], step_id: options[:step_id]
            )
            return JsonPrinter.failure(stderr, **TaskSupport.error_payload(result)) if result.err?

            Owl::Steps::Internal::ActiveStepLock.clear(root: root)
            emit_success(stdout: stdout, result: result, root: root, options: options)
          rescue OptionParser::ParseError => e
            JsonPrinter.failure(stderr, code: :invalid_arguments, message: e.message)
          end

          def emit_success(stdout:, result:, root:, options:)
            payload = {
              ok: true, task_id: options[:task_id], step: result.value[:step],
              resolved_task_id_source: options[:resolved_task_id_source],
              resolved_step_id_source: options[:resolved_step_id_source]
            }
            paths = Owl::Steps::Api.local_paths(root: root, task_id: options[:task_id])
            payload[:task_path] = paths.value[:task_file].task_path if paths.ok?
            JsonPrinter.success(stdout, payload)
          end

          def handle_drift(root:, options:, stderr:)
            events = Owl::Steps::Internal::DriftDetector.call(
              root: root, task_id: options[:task_id], step_id: options[:step_id]
            )
            policy = resolve_drift_policy(root: root, options: options)
            DriftWarningPrinter.call_with_policy(
              events, policy: policy, stderr: stderr,
                      task_id: options[:task_id], step_id: options[:step_id]
            )
          end

          def resolve_drift_policy(root:, options:)
            override = options[:ignore_modification] ? true : false
            bundle = Owl::Steps::Api.show(
              root: root, task_id: options[:task_id], step_id: options[:step_id]
            )
            step_payload = bundle.ok? ? bundle.value[:step] : nil
            Owl::Steps::Internal::DriftPolicy.for(step_payload, override_ignore: override)
          end

          def lock_mismatch_response(root:, options:, stderr:)
            lock = Owl::Steps::Internal::ActiveStepLock.load(root: root)
            return nil unless lock.ok? && lock.value
            return nil if Owl::Steps::Internal::ActiveStepLock.matches?(
              lock.value, task_id: options[:task_id], step_id: options[:step_id]
            )

            JsonPrinter.failure(
              stderr,
              code: :active_step_mismatch,
              message: 'Active-step lock relates to a different step.',
              details: {
                locked_task_id: lock.value['task_id'],
                locked_step_id: lock.value['step_id'],
                requested_task_id: options[:task_id],
                requested_step_id: options[:step_id]
              },
              error_class: :recoverable
            )
          end

          def parse_options(argv)
            options = { root: nil, task_id: nil, step_id: nil, ignore_modification: false }
            parser = OptionParser.new do |opts|
              opts.banner = 'Usage: owl step complete TASK-ID STEP-ID [--ignore-modification] [--root PATH] [--json]'
              opts.on('--ignore-modification', 'Suppress artifact_modified_after_complete warnings') do
                options[:ignore_modification] = true
              end
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
