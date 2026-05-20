# frozen_string_literal: true

require 'optparse'

require_relative '../../../steps/api'
require_relative '../json_printer'
require_relative 'task_support'

module Owl
  module Cli
    module Internal
      module Commands
        module StepStart
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

            result = Owl::Steps::Api.start(
              root: root,
              task_id: options[:task_id],
              step_id: options[:step_id],
              variant: options[:variant]
            )
            return JsonPrinter.failure(stderr, **TaskSupport.error_payload(result)) if result.err?

            payload = {
              ok: true,
              task_id: options[:task_id],
              step: result.value[:step]
            }
            paths = Owl::Steps::Api.local_paths(root: root, task_id: options[:task_id])
            payload[:task_path] = paths.value[:task_file].task_path if paths.ok?
            JsonPrinter.success(stdout, payload)
          rescue OptionParser::ParseError => e
            JsonPrinter.failure(stderr, code: :invalid_arguments, message: e.message)
          end

          def parse_options(argv)
            options = { root: nil, task_id: nil, step_id: nil, variant: nil }
            parser = OptionParser.new do |opts|
              opts.banner = 'Usage: owl step start TASK-ID STEP-ID [--variant NAME] [--root PATH] [--json]'
              opts.on('--variant NAME', String) { |v| options[:variant] = v }
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
