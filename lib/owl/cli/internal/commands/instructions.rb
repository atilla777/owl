# frozen_string_literal: true

require 'optparse'

require_relative '../../../instructions/api'
require_relative '../../../result'
require_relative '../json_printer'
require_relative 'task_support'

module Owl
  module Cli
    module Internal
      module Commands
        module Instructions
          module_function

          def run(argv:, stdout:, stderr:, cwd:, env: ENV.to_h) # rubocop:disable Lint/UnusedMethodArgument
            options, positional = parse_options(argv)
            root = TaskSupport.resolve_root(options[:root], cwd, stderr: stderr)
            return root if root.is_a?(Integer)

            terminal = TaskSupport.reject_if_terminal(root: root, task_id: positional.first, stderr: stderr)
            return terminal if terminal

            result = Owl::Instructions::Api.build_payload(
              root: root, task_id: positional.first, step_id: options[:step_id]
            )
            return JsonPrinter.failure(stderr, **TaskSupport.error_payload(result)) if result.err?

            JsonPrinter.success(stdout, result.value)
          rescue OptionParser::ParseError => e
            JsonPrinter.failure(stderr, code: :invalid_arguments, message: e.message)
          end

          def parse_options(argv)
            options = { root: nil, step_id: nil }
            parser = OptionParser.new do |opts|
              opts.banner = 'Usage: owl instructions [TASK-ID] [--step-id STEP] [--root PATH] [--json]'
              opts.on('--root PATH', String) { |v| options[:root] = v }
              opts.on('--step-id STEP', String) { |v| options[:step_id] = v }
              opts.on('--json', 'Force JSON output (default)') { options[:json] = true }
            end
            positional = parser.parse(argv)
            [options, positional]
          end
        end
      end
    end
  end
end
