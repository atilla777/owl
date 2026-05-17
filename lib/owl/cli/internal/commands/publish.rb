# frozen_string_literal: true

require 'optparse'

require_relative '../../../publish/api'
require_relative '../json_printer'
require_relative 'task_support'

module Owl
  module Cli
    module Internal
      module Commands
        module Publish
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

            result = Owl::Publish::Api.run(
              root: root, task_id: task_id, dry_run: options[:dry_run]
            )
            return JsonPrinter.failure(stderr, **TaskSupport.error_payload(result)) if result.err?

            JsonPrinter.success(stdout, {
                                  ok: true,
                                  task_id: result.value[:task_id],
                                  workflow_key: result.value[:workflow_key],
                                  dry_run: result.value[:dry_run],
                                  step_status: result.value[:step_status],
                                  results: result.value[:results]
                                })
          rescue OptionParser::ParseError => e
            JsonPrinter.failure(stderr, code: :invalid_arguments, message: e.message)
          end

          def parse_options(argv)
            options = { root: nil, dry_run: false }
            parser = OptionParser.new do |opts|
              opts.banner = 'Usage: owl publish TASK-ID [--dry-run] [--root PATH] [--json]'
              opts.on('--root PATH', String) { |v| options[:root] = v }
              opts.on('--dry-run', 'Resolve and print the publish plan without modifying any files.') do
                options[:dry_run] = true
              end
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
