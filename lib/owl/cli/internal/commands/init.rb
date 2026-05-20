# frozen_string_literal: true

require 'optparse'

require_relative '../../../init/api'
require_relative '../json_printer'
require_relative 'task_support'

module Owl
  module Cli
    module Internal
      module Commands
        module Init
          module_function

          def run(argv:, stdout:, stderr:, cwd:, env: ENV.to_h) # rubocop:disable Lint/UnusedMethodArgument
            options = parse_options(argv)
            result = Owl::Init::Api.scaffold(root: options[:root] || cwd, force: options[:force])
            return JsonPrinter.failure(stderr, **TaskSupport.error_payload(result)) if result.err?

            JsonPrinter.success(stdout, { ok: true, **result.value })
          rescue OptionParser::ParseError => e
            JsonPrinter.failure(stderr, code: :invalid_arguments, message: e.message)
          end

          def parse_options(argv)
            options = { root: nil, force: false }
            parser = OptionParser.new do |opts|
              opts.banner = 'Usage: owl init [--root PATH] [--force]'
              opts.on('--root PATH', String, 'Project root (default: cwd)') { |v| options[:root] = v }
              opts.on('--force', 'Overwrite existing files') { options[:force] = true }
              opts.on('--json', 'Force JSON output (default)') { options[:json] = true }
            end
            parser.parse!(argv)
            options
          end
        end
      end
    end
  end
end
