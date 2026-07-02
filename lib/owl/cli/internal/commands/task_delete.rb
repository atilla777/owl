# frozen_string_literal: true

require 'optparse'

require_relative '../../../tasks/api'
require_relative '../json_printer'
require_relative 'task_support'

module Owl
  module Cli
    module Internal
      module Commands
        module TaskDelete
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

            unless options[:force]
              return JsonPrinter.failure(
                stderr,
                code: :confirmation_required,
                message: "pass --force to physically remove #{options[:task_id]}; this is irreversible",
                details: { task_id: options[:task_id] }
              )
            end

            root = TaskSupport.resolve_root(options[:root], cwd, stderr: stderr)
            return root if root.is_a?(Integer)

            stderr.puts("WARNING: physical task deletion is irreversible: #{options[:task_id]}")

            result = Owl::Tasks::Api.delete(root: root, task_id: options[:task_id], recursive: options[:recursive])
            return JsonPrinter.failure(stderr, **TaskSupport.error_payload(result)) if result.err?

            JsonPrinter.success(stdout, {
                                  ok: true,
                                  task_id: result.value[:task_id],
                                  removed: result.value[:removed] == true,
                                  removed_task_ids: Array(result.value[:removed_task_ids])
                                })
          rescue OptionParser::ParseError => e
            JsonPrinter.failure(stderr, code: :invalid_arguments, message: e.message)
          end

          def parse_options(argv)
            options = { root: nil, task_id: nil, force: false, recursive: false }
            parser = OptionParser.new do |opts|
              opts.banner = 'Usage: owl task delete TASK-ID --force [--recursive] [--root PATH] [--json]'
              opts.on('--force', 'Required: confirms irreversible physical deletion') { options[:force] = true }
              opts.on('--recursive', 'Delete the whole subtree (composite parent + all descendants)') do
                options[:recursive] = true
              end
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
