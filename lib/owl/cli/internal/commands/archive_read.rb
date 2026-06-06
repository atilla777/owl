# frozen_string_literal: true

require 'optparse'

require_relative '../../../archive/api'
require_relative '../json_printer'
require_relative 'task_support'

module Owl
  module Cli
    module Internal
      module Commands
        module ArchiveRead
          module_function

          def run(argv:, stdout:, stderr:, cwd:, env: ENV.to_h) # rubocop:disable Lint/UnusedMethodArgument
            options, positional = parse_options(argv)
            task_id, artifact_key = positional
            unless task_id && artifact_key
              return JsonPrinter.failure(
                stderr,
                code: :invalid_arguments,
                message: 'TASK-ID and ARTIFACT-KEY positional arguments are required.'
              )
            end

            root = TaskSupport.resolve_root(options[:root], cwd, stderr: stderr)
            return root if root.is_a?(Integer)

            result = Owl::Archive::Api.read(root: root, task_id: task_id, artifact_key: artifact_key)
            return JsonPrinter.failure(stderr, **TaskSupport.error_payload(result)) if result.err?

            return print_body(stdout, result.value[:body]) unless options[:json]

            JsonPrinter.success(stdout, {
                                  ok: true,
                                  task_id: result.value[:task_id],
                                  artifact_key: result.value[:artifact_key],
                                  path: result.value[:path],
                                  body: result.value[:body]
                                })
          rescue OptionParser::ParseError => e
            JsonPrinter.failure(stderr, code: :invalid_arguments, message: e.message)
          end

          def print_body(stdout, body)
            stdout.print(body)
            0
          end

          def parse_options(argv)
            options = { root: nil, json: true }
            parser = OptionParser.new do |opts|
              opts.banner = 'Usage: owl archive read TASK-ID ARTIFACT-KEY [--root PATH] [--json|--no-json]'
              opts.on('--root PATH', String) { |v| options[:root] = v }
              opts.on('--[no-]json', 'Emit JSON (default) or print the raw artifact body') { |v| options[:json] = v }
            end
            positional = parser.parse(argv)
            [options, positional]
          end
        end
      end
    end
  end
end
