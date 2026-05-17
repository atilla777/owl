# frozen_string_literal: true

require 'optparse'

require_relative '../../../tasks/api'
require_relative '../json_printer'
require_relative 'task_support'

module Owl
  module Cli
    module Internal
      module Commands
        module TaskSplit
          module_function

          def run(argv:, stdout:, stderr:, cwd:, env: ENV.to_h) # rubocop:disable Lint/UnusedMethodArgument
            options, positional = parse_options(argv)
            task_id = positional.first
            unless task_id
              return JsonPrinter.failure(
                stderr,
                code: :invalid_arguments,
                message: 'TASK-ID positional argument is required.'
              )
            end

            root = TaskSupport.resolve_root(options[:root], cwd, stderr: stderr)
            return root if root.is_a?(Integer)

            result = Owl::Tasks::Api.split(root: root, task_id: task_id, kind: options[:kind])
            return JsonPrinter.failure(stderr, **TaskSupport.error_payload(result)) if result.err?

            JsonPrinter.success(stdout, {
                                  ok: true,
                                  task_id: result.value[:task_id],
                                  kind: result.value[:kind],
                                  changed: result.value[:changed]
                                })
          rescue OptionParser::ParseError => e
            JsonPrinter.failure(stderr, code: :invalid_arguments, message: e.message)
          end

          def parse_options(argv)
            options = { root: nil, kind: 'composite_task' }
            parser = OptionParser.new do |opts|
              opts.banner = 'Usage: owl task split TASK-ID [--kind composite_task] [--root PATH] [--json]'
              opts.on('--kind KIND', String) { |v| options[:kind] = v }
              opts.on('--root PATH', String) { |v| options[:root] = v }
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
