# frozen_string_literal: true

require 'optparse'

require_relative '../../../tasks/api'
require_relative '../json_printer'
require_relative 'task_support'

module Owl
  module Cli
    module Internal
      module Commands
        # `owl task dep <add|rm|list> TASK-ID [--on DEP]`. `add` declares
        # `TASK-ID` blocked_by `DEP`; `rm` removes that edge (no-op if absent);
        # `list` reports `{ blocked_by, blocks }` (dependents computed by reverse
        # index scan).
        module TaskDep
          module_function

          def add(argv:, stdout:, stderr:, cwd:, env: ENV.to_h)
            run_edge(:add, argv: argv, stdout: stdout, stderr: stderr, cwd: cwd, env: env)
          end

          def rm(argv:, stdout:, stderr:, cwd:, env: ENV.to_h)
            run_edge(:remove, argv: argv, stdout: stdout, stderr: stderr, cwd: cwd, env: env)
          end

          def run_edge(action, argv:, stdout:, stderr:, cwd:, env: ENV.to_h) # rubocop:disable Lint/UnusedMethodArgument
            options, positional = parse_options(argv)
            task_id = positional.first
            depends_on = options[:on]
            unless task_id && depends_on
              return JsonPrinter.failure(
                stderr,
                code: :invalid_arguments,
                message: 'TASK-ID positional and --on DEP are required.'
              )
            end

            root = TaskSupport.resolve_root(options[:root], cwd, stderr: stderr)
            return root if root.is_a?(Integer)

            result =
              if action == :add
                Owl::Tasks::Api.add_dependency(root: root, task_id: task_id, depends_on: depends_on)
              else
                Owl::Tasks::Api.remove_dependency(root: root, task_id: task_id, depends_on: depends_on)
              end
            return JsonPrinter.failure(stderr, **TaskSupport.error_payload(result)) if result.err?

            JsonPrinter.success(stdout, {
                                  ok: true,
                                  task_id: result.value[:task_id],
                                  blocked_by: result.value[:blocked_by]
                                })
          rescue OptionParser::ParseError => e
            JsonPrinter.failure(stderr, code: :invalid_arguments, message: e.message)
          end

          def list(argv:, stdout:, stderr:, cwd:, env: ENV.to_h) # rubocop:disable Lint/UnusedMethodArgument
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

            result = Owl::Tasks::Api.dependencies(root: root, task_id: task_id)
            return JsonPrinter.failure(stderr, **TaskSupport.error_payload(result)) if result.err?

            JsonPrinter.success(stdout, {
                                  ok: true,
                                  task_id: result.value[:task_id],
                                  blocked_by: result.value[:blocked_by],
                                  blocks: result.value[:blocks]
                                })
          rescue OptionParser::ParseError => e
            JsonPrinter.failure(stderr, code: :invalid_arguments, message: e.message)
          end

          def parse_options(argv)
            options = { root: nil, on: nil }
            parser = OptionParser.new do |opts|
              opts.banner = 'Usage: owl task dep <add|rm|list> TASK-ID [--on DEP] [--root PATH] [--json]'
              opts.on('--on DEP', String) { |v| options[:on] = v }
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
