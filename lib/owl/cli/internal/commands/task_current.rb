# frozen_string_literal: true

require 'optparse'

require_relative '../../../tasks/api'
require_relative '../json_printer'
require_relative 'task_support'

module Owl
  module Cli
    module Internal
      module Commands
        module TaskCurrent
          module_function

          def run(argv:, stdout:, stderr:, cwd:, env: ENV.to_h) # rubocop:disable Lint/UnusedMethodArgument
            options = parse_options(argv)
            root = TaskSupport.resolve_root(options[:root], cwd, stderr: stderr)
            return root if root.is_a?(Integer)

            result = Owl::Tasks::Api.current(root: root)
            return JsonPrinter.failure(stderr, **TaskSupport.error_payload(result)) if result.err?

            payload = {
              ok: true,
              task_id: result.value[:task_id],
              set_at: result.value[:set_at]
            }
            paths = Owl::Tasks::Api.local_paths(root: root, task_id: result.value[:task_id])
            payload[:pointer_path] = paths.value[:pointer].pointer_path if paths.ok?
            payload[:task] = result.value[:payload]
            payload[:task_path] = paths.value[:task_file].task_path if paths.ok?
            JsonPrinter.success(stdout, payload)
          rescue OptionParser::ParseError => e
            JsonPrinter.failure(stderr, code: :invalid_arguments, message: e.message)
          end

          def parse_options(argv)
            options = { root: nil }
            parser = OptionParser.new do |opts|
              opts.banner = 'Usage: owl task current [--root PATH] [--json]'
              opts.on('--root PATH', String) { |v| options[:root] = v }
              opts.on('--json', 'Force JSON output (default)') { options[:json] = true }
            end
            parser.parse!(argv)
            options
          end
        end
      end
    end
  end
end
