# frozen_string_literal: true

require 'optparse'

require_relative '../../../tasks/api'
require_relative '../json_printer'
require_relative 'task_support'

module Owl
  module Cli
    module Internal
      module Commands
        module TaskAbandon
          module_function

          def run(argv:, stdout:, stderr:, cwd:, env: ENV.to_h) # rubocop:disable Lint/UnusedMethodArgument
            options = parse_options(argv)
            unless options[:task_id]
              return JsonPrinter.failure(
                stderr,
                code: :invalid_arguments,
                message: 'TASK-ID is required.'
              )
            end

            root = TaskSupport.resolve_root(options[:root], cwd, stderr: stderr)
            return root if root.is_a?(Integer)

            result = Owl::Tasks::Api.abandon(
              root: root,
              task_id: options[:task_id],
              reason: options[:reason]
            )
            return JsonPrinter.failure(stderr, **TaskSupport.error_payload(result)) if result.err?

            payload = {
              ok: true,
              task_id: result.value[:task_id],
              status: result.value[:status],
              abandoned_at: result.value[:abandoned_at]
            }
            payload[:abandon_reason] = result.value[:abandon_reason] if result.value[:abandon_reason]
            payload[:idempotent] = true if result.value[:idempotent]
            JsonPrinter.success(stdout, payload)
          rescue OptionParser::ParseError => e
            JsonPrinter.failure(stderr, code: :invalid_arguments, message: e.message)
          end

          def parse_options(argv)
            options = { root: nil, task_id: nil, reason: nil }
            parser = OptionParser.new do |opts|
              opts.banner = 'Usage: owl task abandon TASK-ID [--reason TEXT] [--root PATH] [--json]'
              opts.on('--reason TEXT', String) { |v| options[:reason] = v }
              opts.on('--root PATH', String) { |v| options[:root] = v }
              opts.on('--json', 'Force JSON output (default)') { options[:json] = true }
            end
            positional = parser.parse(argv)
            options[:task_id] = positional[0]
            options
          end
        end
      end
    end
  end
end
