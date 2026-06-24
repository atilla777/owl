# frozen_string_literal: true

require 'optparse'

require_relative '../../../workflows/api'
require_relative '../json_printer'
require_relative 'task_support'

module Owl
  module Cli
    module Internal
      module Commands
        module TaskReadySteps
          module_function

          def run(argv:, stdout:, stderr:, cwd:, env: ENV.to_h) # rubocop:disable Lint/UnusedMethodArgument
            options = parse_options(argv)
            task_id = options[:task_id]
            unless task_id
              return JsonPrinter.failure(
                stderr,
                code: :invalid_arguments,
                message: 'TASK-ID is required.'
              )
            end

            root = TaskSupport.resolve_root(options[:root], cwd, stderr: stderr)
            return root if root.is_a?(Integer)

            result = Owl::Workflows::Api.ready_steps(root: root, task_id: task_id)
            return JsonPrinter.failure(stderr, **TaskSupport.error_payload(result)) if result.err?

            JsonPrinter.success(stdout, {
                                  ok: true,
                                  task_id: result.value[:task_id],
                                  workflow_key: result.value[:workflow_key],
                                  ready: result.value[:ready],
                                  blocked_by_children: Array(result.value[:blocked_by_children]),
                                  awaiting_plan_approval: Array(result.value[:awaiting_plan_approval]),
                                  conditional_skip: Array(result.value[:conditional_skip])
                                })
          rescue OptionParser::ParseError => e
            JsonPrinter.failure(stderr, code: :invalid_arguments, message: e.message)
          end

          def parse_options(argv)
            options = { root: nil, task_id: nil }
            parser = OptionParser.new do |opts|
              opts.banner = 'Usage: owl task ready-steps TASK-ID [--root PATH] [--json]'
              opts.on('--root PATH', String) { |v| options[:root] = v }
              opts.on('--json', 'Force JSON output (default)') { options[:json] = true }
            end
            positional = parser.parse(argv)
            options[:task_id] = positional.first
            options
          end
        end
      end
    end
  end
end
