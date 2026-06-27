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
        module ConfigSet
          module_function

          def run(argv:, stdout:, stderr:, cwd:, env: ENV.to_h) # rubocop:disable Lint/UnusedMethodArgument
            options = parse_options(argv)

            if options[:key].nil? || options[:value].nil?
              return JsonPrinter.failure(stderr, code: :invalid_arguments,
                                                 message: 'Usage: owl config set KEY VALUE [--root PATH] [--json]')
            end

            root_result = resolve_root(options[:root], cwd, stderr: stderr)
            return root_result if root_result.is_a?(Integer)

            result = Owl::Config::Api.write_key(root: root_result, key: options[:key], value: options[:value])
            if result.ok?
              JsonPrinter.success(stdout, ok: true, key: result.value[:key], value: result.value[:value])
            else
              JsonPrinter.failure(stderr, code: result.code, message: result.message,
                                          details: sanitize_details(result.details))
            end
          rescue OptionParser::ParseError => e
            JsonPrinter.failure(stderr, code: :invalid_arguments, message: e.message)
          end

          def parse_options(argv)
            options = { root: nil, key: nil, value: nil }
            parser = OptionParser.new do |opts|
              opts.banner = 'Usage: owl config set KEY VALUE [--root PATH] [--json]'
              opts.on('--root PATH', String, 'Project root (default: auto-detect from cwd)') { |v| options[:root] = v }
              opts.on('--json', 'Force JSON output (default)') { options[:json] = true }
            end
            remaining = parser.parse(argv)
            options[:key] = remaining.shift
            options[:value] = remaining.shift
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

          def sanitize_details(details)
            return details unless details.is_a?(Hash)

            details.except(:document, 'document')
          end
        end
      end
    end
  end
end
