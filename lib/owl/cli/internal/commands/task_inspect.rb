# frozen_string_literal: true

require 'optparse'

require_relative '../../../tasks/api'
require_relative '../json_printer'
require_relative 'task_support'

module Owl
  module Cli
    module Internal
      module Commands
        module TaskInspect
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

            result = Owl::Tasks::Api.inspect(root: root, task_id: task_id)
            return JsonPrinter.failure(stderr, **TaskSupport.error_payload(result)) if result.err?

            payload = { ok: true, task: result.value[:payload] }
            paths = Owl::Tasks::Api.local_paths(root: root, task_id: task_id)
            payload[:task_path] = paths.value[:task_file].task_path if paths.ok?
            JsonPrinter.success(stdout, payload)
          rescue OptionParser::ParseError => e
            JsonPrinter.failure(stderr, code: :invalid_arguments, message: e.message)
          end

          def parse_options(argv)
            options = { root: nil }
            parser = OptionParser.new do |opts|
              opts.banner = 'Usage: owl task inspect TASK-ID [--root PATH] [--json]'
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
