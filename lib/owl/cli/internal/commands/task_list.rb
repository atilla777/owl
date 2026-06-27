# frozen_string_literal: true

require 'optparse'

require_relative '../../../tasks/api'
require_relative '../json_printer'
require_relative 'task_support'

module Owl
  module Cli
    module Internal
      module Commands
        module TaskList
          module_function

          def run(argv:, stdout:, stderr:, cwd:, env: ENV.to_h) # rubocop:disable Lint/UnusedMethodArgument
            options = parse_options(argv)
            root = TaskSupport.resolve_root(options[:root], cwd, stderr: stderr)
            return root if root.is_a?(Integer)

            result = Owl::Tasks::Api.list(root: root)
            return JsonPrinter.failure(stderr, **TaskSupport.error_payload(result)) if result.err?

            tasks = result.value[:tasks]
            tasks = tasks.reject { |t| t['status'] == 'abandoned' } unless options[:include_abandoned]

            payload = { ok: true }
            paths = Owl::Tasks::Api.local_paths(root: root)
            payload[:index_path] = paths.value[:index].index_path if paths.ok?
            payload[:schema_version] = result.value[:schema_version]
            payload[:tasks] = tasks
            JsonPrinter.success(stdout, payload)
          rescue OptionParser::ParseError => e
            JsonPrinter.failure(stderr, code: :invalid_arguments, message: e.message)
          end

          def parse_options(argv)
            options = { root: nil, include_abandoned: false }
            parser = OptionParser.new do |opts|
              opts.banner = 'Usage: owl task list [--include-abandoned] [--root PATH] [--json]'
              opts.on('--include-abandoned', 'Include tasks with status: abandoned') do
                options[:include_abandoned] = true
              end
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
