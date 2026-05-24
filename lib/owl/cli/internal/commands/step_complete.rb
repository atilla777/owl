# frozen_string_literal: true

require 'json'
require 'optparse'

require_relative '../../../steps/api'
require_relative '../../../steps/internal/active_step_lock'
require_relative '../../../steps/internal/drift_detector'
require_relative '../json_printer'
require_relative 'drift_warning_printer'
require_relative 'task_support'

module Owl
  module Cli
    module Internal
      module Commands
        module StepComplete
          module_function

          def run(argv:, stdout:, stderr:, cwd:, env: ENV.to_h) # rubocop:disable Lint/UnusedMethodArgument
            options = parse_options(argv)
            unless options[:task_id] && options[:step_id]
              return JsonPrinter.failure(
                stderr,
                code: :invalid_arguments,
                message: 'TASK-ID and STEP-ID are required.'
              )
            end

            root = TaskSupport.resolve_root(options[:root], cwd, stderr: stderr)
            return root if root.is_a?(Integer)

            unless options[:ignore_modification]
              events = Owl::Steps::Internal::DriftDetector.call(
                root: root, task_id: options[:task_id], step_id: options[:step_id]
              )
              DriftWarningPrinter.call(events, stderr: stderr)
            end

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
            payload = { ok: true, task_id: options[:task_id], step: result.value[:step] }
            paths = Owl::Steps::Api.local_paths(root: root, task_id: options[:task_id])
            payload[:task_path] = paths.value[:task_file].task_path if paths.ok?
            JsonPrinter.success(stdout, payload)
          end

          def lock_mismatch_response(root:, options:, stderr:)
            lock = Owl::Steps::Internal::ActiveStepLock.load(root: root)
            return nil unless lock.ok? && lock.value
            return nil if Owl::Steps::Internal::ActiveStepLock.matches?(
              lock.value, task_id: options[:task_id], step_id: options[:step_id]
            )

            stderr.puts(JSON.generate({
                                        ok: false,
                                        error: {
                                          code: 'active_step_mismatch',
                                          message: 'Active-step lock relates to a different step.',
                                          details: {
                                            locked_task_id: lock.value['task_id'],
                                            locked_step_id: lock.value['step_id'],
                                            requested_task_id: options[:task_id],
                                            requested_step_id: options[:step_id]
                                          }
                                        }
                                      }))
            2
          end

          def parse_options(argv)
            options = { root: nil, task_id: nil, step_id: nil, ignore_modification: false }
            parser = OptionParser.new do |opts|
              opts.banner = 'Usage: owl step complete TASK-ID STEP-ID [--ignore-modification] [--root PATH] [--json]'
              opts.on('--ignore-modification', 'Suppress artifact_modified_after_complete warnings') { options[:ignore_modification] = true }
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
