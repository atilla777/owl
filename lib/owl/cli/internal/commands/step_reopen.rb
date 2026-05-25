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
        module StepReopen
          module_function

          def run(argv:, stdout:, stderr:, cwd:, env: ENV.to_h) # rubocop:disable Lint/UnusedMethodArgument
            options = parse_options(argv)

            root = TaskSupport.resolve_root(options[:root], cwd, stderr: stderr)
            return root if root.is_a?(Integer)

            resolution = StepIdResolver.apply!(root: root, options: options, allow_running_inference: true)
            return JsonPrinter.failure(stderr, **TaskSupport.error_payload(resolution)) if resolution.err?

            result = Owl::Steps::Api.reopen(
              root: root,
              task_id: options[:task_id],
              step_id: options[:step_id],
              cascade: options[:cascade]
            )
            return JsonPrinter.failure(stderr, **TaskSupport.error_payload(result)) if result.err?

            JsonPrinter.success(stdout, {
                                  ok: true,
                                  task_id: options[:task_id],
                                  reopened: result.value[:reopened],
                                  resolved_task_id_source: options[:resolved_task_id_source],
                                  resolved_step_id_source: options[:resolved_step_id_source]
                                })
          rescue OptionParser::ParseError => e
            JsonPrinter.failure(stderr, code: :invalid_arguments, message: e.message)
          end

          def parse_options(argv)
            options = { root: nil, task_id: nil, step_id: nil, cascade: false }
            parser = OptionParser.new do |opts|
              opts.banner = 'Usage: owl step reopen TASK-ID STEP-ID [--cascade] [--root PATH] [--json]'
              opts.on('--cascade', 'Also pendify every step that transitively requires this one') do
                options[:cascade] = true
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
