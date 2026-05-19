# frozen_string_literal: true

require 'optparse'
require 'pathname'

require_relative '../../../config/api'
require_relative '../../../storage/api'
require_relative '../json_printer'

module Owl
  module Cli
    module Internal
      module Commands
        module ConfigShow
          module_function

          def run(argv:, stdout:, stderr:, cwd:, env: ENV.to_h) # rubocop:disable Lint/UnusedMethodArgument
            options = parse_options(argv)
            root_result = resolve_root(options[:root], cwd, stderr: stderr)
            return root_result if root_result.is_a?(Integer)

            result = Owl::Config::Api.snapshot(root: root_result)
            if result.ok?
              payload = result.value.merge(ok: true, root: root_result.to_s)
              JsonPrinter.success(stdout, payload)
            else
              JsonPrinter.failure(stderr, code: result.code, message: result.message, details: result.details)
            end
          rescue OptionParser::ParseError => e
            JsonPrinter.failure(stderr, code: :invalid_arguments, message: e.message)
          end

          def parse_options(argv)
            options = { root: nil }
            parser = OptionParser.new do |opts|
              opts.banner = 'Usage: owl config show [--root PATH] [--json]'
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
              if detect_result.err?
                return JsonPrinter.failure(stderr, code: detect_result.code, message: detect_result.message,
                                                   details: detect_result.details)
              end

              detect_result.value
            end
          end
        end
      end
    end
  end
end
