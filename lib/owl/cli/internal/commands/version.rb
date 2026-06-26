# frozen_string_literal: true

require 'optparse'
require 'pathname'

require_relative '../../../version/api'
require_relative '../../../storage/api'
require_relative '../json_printer'

module Owl
  module Cli
    module Internal
      module Commands
        # `owl version` — prints both the running gem version and the
        # project-stamped `owl.version`, signalling drift via `up_to_date`.
        # Distinct from the `owl --version` flag, which only prints the gem.
        module Version
          module_function

          def run(argv:, stdout:, stderr:, cwd:, env: ENV.to_h) # rubocop:disable Lint/UnusedMethodArgument
            options = parse_options(argv)
            root_result = resolve_root(options[:root], cwd, stderr: stderr)
            return root_result if root_result.is_a?(Integer)

            result = Owl::Version::Api.info(root: root_result)
            if result.ok?
              JsonPrinter.success(stdout, ok: true, gem: result.value[:gem],
                                          project: result.value[:project], up_to_date: result.value[:up_to_date])
            else
              JsonPrinter.failure(stderr, code: result.code, message: result.message, details: result.details)
            end
          rescue OptionParser::ParseError => e
            JsonPrinter.failure(stderr, code: :invalid_arguments, message: e.message)
          end

          def parse_options(argv)
            options = { root: nil }
            parser = OptionParser.new do |opts|
              opts.banner = 'Usage: owl version [--root PATH] [--json]'
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
