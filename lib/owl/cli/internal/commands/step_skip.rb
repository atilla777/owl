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
