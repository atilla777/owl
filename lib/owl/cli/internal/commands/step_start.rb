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
        module StepStart
          module_function

          def run(argv:, stdout:, stderr:, cwd:, env: ENV.to_h) # rubocop:disable Lint/UnusedMethodArgument
            options = parse_options(argv)

            root = TaskSupport.resolve_root(options[:root], cwd, stderr: stderr)
            return root if root.is_a?(Integer)

            resolution = StepIdResolver.apply!(root: root, options: options, allow_running_inference: false)
            return JsonPrinter.failure(stderr, **TaskSupport.error_payload(resolution)) if resolution.err?

            unless options[:force]
              lock_block = check_existing_lock(root: root, options: options, stderr: stderr)
              return lock_block if lock_block
            end

            drift_block = handle_drift(root: root, options: options, stderr: stderr)
            return drift_block if drift_block

            result = Owl::Steps::Api.start(
              root: root, task_id: options[:task_id], step_id: options[:step_id],
              variant: options[:variant]
            )
            return JsonPrinter.failure(stderr, **TaskSupport.error_payload(result)) if result.err?

            write_active_step_lock(root: root, options: options)
            emit_success(stdout: stdout, result: result, root: root, options: options)
          rescue OptionParser::ParseError => e
            JsonPrinter.failure(stderr, code: :invalid_arguments, message: e.message)
          end

          def check_existing_lock(root:, options:, stderr:)
            existing = Owl::Steps::Internal::ActiveStepLock.load(root: root, task_id: options[:task_id])
            return nil unless existing.ok? && existing.value
            return nil if Owl::Steps::Internal::ActiveStepLock.matches?(
              existing.value, task_id: options[:task_id], step_id: options[:step_id]
            )

            JsonPrinter.failure(
              stderr,
              code: :active_step_locked,
              message: 'Another step is already locked. Use --force to override.',
              details: {
                locked_task_id: existing.value['task_id'],
                locked_step_id: existing.value['step_id'],
                requested_task_id: options[:task_id],
                requested_step_id: options[:step_id]
              },
              error_class: :recoverable
            )
          end

          def write_active_step_lock(root:, options:)
            session_type = resolve_session_type(root: root, options: options)
            Owl::Steps::Internal::ActiveStepLock.write(
              root: root, task_id: options[:task_id], step_id: options[:step_id],
              session_type: session_type, variant: options[:variant]
            )
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

          # Runs DriftDetector + DriftPolicy. Returns nil when the step may
          # continue, or an Integer exit code when policy=:block forces an
          # abort. RFC #1 §4 follow-up.
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

          # Pulls session_type out of the step bundle for the lock-file record.
          # Falls back to 'execution' (the StepProjection default) when the
          # bundle cannot be resolved — the lock then carries the conservative
          # value rather than failing the start path.
          def resolve_session_type(root:, options:)
            bundle = Owl::Steps::Api.show(
              root: root, task_id: options[:task_id], step_id: options[:step_id]
            )
            return 'execution' if bundle.err?

            bundle.value[:step]['session_type'] || 'execution'
          end

          def parse_options(argv)
            options = {
              root: nil, task_id: nil, step_id: nil, variant: nil,
              ignore_modification: false, force: false
            }
            parser = OptionParser.new do |opts|
              opts.banner = <<~BANNER
                Usage: owl step start TASK-ID STEP-ID [--variant NAME] [--force] [--ignore-modification] [--root PATH] [--json]
              BANNER
              opts.on('--variant NAME', String) { |v| options[:variant] = v }
              opts.on('--force', 'Override an existing active-step lock for a different step') do
                options[:force] = true
              end
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
