# frozen_string_literal: true

require 'optparse'

require_relative '../../../tasks/api'
require_relative '../json_printer'
require_relative 'task_support'

module Owl
  module Cli
    module Internal
      module Commands
        # `owl task label add|rm TASK-ID LABEL`. `add` is idempotent; `rm` of an
        # absent label is a clean no-op.
        module TaskLabel
          module_function

          def add(argv:, stdout:, stderr:, cwd:, env: ENV.to_h)
            run(:add, argv: argv, stdout: stdout, stderr: stderr, cwd: cwd, env: env)
          end

          def rm(argv:, stdout:, stderr:, cwd:, env: ENV.to_h)
            run(:remove, argv: argv, stdout: stdout, stderr: stderr, cwd: cwd, env: env)
          end

          def run(action, argv:, stdout:, stderr:, cwd:, env: ENV.to_h) # rubocop:disable Lint/UnusedMethodArgument
            options, positional = parse_options(argv)
            task_id = positional[0]
            label = positional[1]
            unless task_id && label
              return JsonPrinter.failure(
                stderr,
                code: :invalid_arguments,
                message: 'TASK-ID and LABEL positional arguments are required.'
              )
            end

            root = TaskSupport.resolve_root(options[:root], cwd, stderr: stderr)
            return root if root.is_a?(Integer)

            result =
              if action == :add
                Owl::Tasks::Api.add_label(root: root, task_id: task_id, label: label)
              else
                Owl::Tasks::Api.remove_label(root: root, task_id: task_id, label: label)
              end
            return JsonPrinter.failure(stderr, **TaskSupport.error_payload(result)) if result.err?

            JsonPrinter.success(stdout, {
                                  ok: true,
                                  task_id: result.value[:task_id],
                                  labels: result.value[:labels]
                                })
          rescue OptionParser::ParseError => e
            JsonPrinter.failure(stderr, code: :invalid_arguments, message: e.message)
          end

          def parse_options(argv)
            options = { root: nil }
            parser = OptionParser.new do |opts|
              opts.banner = 'Usage: owl task label <add|rm> TASK-ID LABEL [--root PATH] [--json]'
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
