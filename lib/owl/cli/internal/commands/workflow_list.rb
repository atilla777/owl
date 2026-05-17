# frozen_string_literal: true

require 'optparse'
require 'pathname'

require_relative '../../../storage/api'
require_relative '../../../workflows/api'
require_relative '../json_printer'

module Owl
  module Cli
    module Internal
      module Commands
        module WorkflowList
          module_function

          def run(argv:, stdout:, stderr:, cwd:, env: ENV.to_h) # rubocop:disable Lint/UnusedMethodArgument
            options = parse_options(argv)
            root_result = resolve_root(options[:root], cwd, stderr: stderr)
            return root_result if root_result.is_a?(Integer)

            root = root_result
            list_result = Owl::Workflows::Api.list(root: root)
            return JsonPrinter.failure(stderr, **error_payload(list_result)) if list_result.err?

            JsonPrinter.success(stdout, {
                                  ok: true,
                                  root: root.to_s,
                                  workflows: list_result.value
                                })
          rescue OptionParser::ParseError => e
            JsonPrinter.failure(stderr, code: :invalid_arguments, message: e.message)
          end

          def parse_options(argv)
            options = { root: nil }
            parser = OptionParser.new do |opts|
              opts.banner = 'Usage: owl workflow list [--root PATH] [--json]'
              opts.on('--root PATH', String, 'Project root (default: auto-detect from cwd)') { |v| options[:root] = v }
              opts.on('--json', 'Force JSON output (default)') { options[:json] = true }
            end
            parser.parse!(argv)
            options
          end

          def resolve_root(explicit_root, cwd, stderr:)
            if explicit_root
              Pathname.new(explicit_root).expand_path
            else
              detect_result = Owl::Storage::Api.detect_root(start: cwd)
              return JsonPrinter.failure(stderr, **error_payload(detect_result)) if detect_result.err?

              detect_result.value
            end
          end

          def error_payload(err_result)
            { code: err_result.code, message: err_result.message, details: err_result.details }
          end
        end
      end
    end
  end
end
