# frozen_string_literal: true

require 'optparse'

require_relative '../../../workflows/api'
require_relative '../json_printer'
require_relative 'task_support'

module Owl
  module Cli
    module Internal
      module Commands
        module WorkflowValidate
          module_function

          def run(argv:, stdout:, stderr:, cwd:, env: ENV.to_h) # rubocop:disable Lint/UnusedMethodArgument
            options, positional = parse_options(argv)
            target = positional[0]
            unless target
              return JsonPrinter.failure(stderr, code: :invalid_arguments,
                                                 message: 'ID-OR-PATH positional argument is required.')
            end

            root = TaskSupport.resolve_root(options[:root], cwd, stderr: stderr)
            return root if root.is_a?(Integer)

            result = Owl::Workflows::Api.validate(root: root, id_or_path: target)
            if result.err?
              return JsonPrinter.failure(
                stderr,
                code: result.code,
                message: result.message,
                details: result.details
              )
            end

            payload = {
              ok: true,
              valid: true,
              id: result.value[:id]
            }
            paths = Owl::Workflows::Api.local_paths(root: root, key: result.value[:id])
            payload[:source_path] = paths.value.source_path if paths.ok?
            payload[:errors] = result.value[:errors]
            JsonPrinter.success(stdout, payload)
          rescue OptionParser::ParseError => e
            JsonPrinter.failure(stderr, code: :invalid_arguments, message: e.message)
          end

          def parse_options(argv)
            options = { root: nil }
            parser = OptionParser.new do |opts|
              opts.banner = 'Usage: owl workflow validate ID-OR-PATH [--root PATH] [--json]'
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
