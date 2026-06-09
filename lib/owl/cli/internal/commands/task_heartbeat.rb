# frozen_string_literal: true

require 'optparse'

require_relative '../../../tasks/api'
require_relative '../json_printer'
require_relative 'task_support'

module Owl
  module Cli
    module Internal
      module Commands
        module TaskHeartbeat
          module_function

          def run(argv:, stdout:, stderr:, cwd:, env: ENV.to_h) # rubocop:disable Lint/UnusedMethodArgument
            options, positional = parse_options(argv)
            task_id = positional.first
            unless task_id && options[:token]
              return JsonPrinter.failure(
                stderr,
                code: :invalid_arguments,
                message: 'TASK-ID positional and --token are required.'
              )
            end

            root = TaskSupport.resolve_root(options[:root], cwd, stderr: stderr)
            return root if root.is_a?(Integer)

            result = Owl::Tasks::Api.heartbeat(root: root, task_id: task_id, token: options[:token], ttl: options[:ttl])
            return JsonPrinter.failure(stderr, **TaskSupport.error_payload(result)) if result.err?

            JsonPrinter.success(stdout, {
                                  ok: true,
                                  task_id: result.value[:task_id],
                                  expires_at: result.value[:expires_at],
                                  heartbeat_at: result.value[:heartbeat_at],
                                  ttl_seconds: result.value[:ttl_seconds]
                                })
          rescue OptionParser::ParseError => e
            JsonPrinter.failure(stderr, code: :invalid_arguments, message: e.message)
          end

          def parse_options(argv)
            options = { root: nil, token: nil, ttl: nil }
            parser = OptionParser.new do |opts|
              opts.banner = 'Usage: owl task heartbeat TASK-ID --token T [--ttl N] [--root PATH] [--json]'
              opts.on('--token T', String) { |v| options[:token] = v }
              opts.on('--ttl N', Integer) { |v| options[:ttl] = v }
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
