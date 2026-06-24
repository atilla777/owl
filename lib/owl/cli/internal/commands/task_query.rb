# frozen_string_literal: true

require 'optparse'

require_relative '../../../tasks/api'
require_relative '../json_printer'
require_relative 'task_support'

module Owl
  module Cli
    module Internal
      module Commands
        # `owl task query [--status S] [--label L] [--priority N] [--parent ID]
        # [--workflow K]`. Combinable AND filters over the materialized index.
        module TaskQuery
          module_function

          def run(argv:, stdout:, stderr:, cwd:, env: ENV.to_h) # rubocop:disable Lint/UnusedMethodArgument
            options = parse_options(argv)
            root = TaskSupport.resolve_root(options[:root], cwd, stderr: stderr)
            return root if root.is_a?(Integer)

            result = Owl::Tasks::Api.query(root: root, filters: options[:filters])
            return JsonPrinter.failure(stderr, **TaskSupport.error_payload(result)) if result.err?

            JsonPrinter.success(stdout, { ok: true, tasks: result.value[:tasks] })
          rescue OptionParser::ParseError => e
            JsonPrinter.failure(stderr, code: :invalid_arguments, message: e.message)
          end

          def parse_options(argv)
            options = { root: nil, filters: {} }
            parser = OptionParser.new do |opts|
              opts.banner = 'Usage: owl task query [--status S] [--label L] [--priority N] ' \
                            '[--parent ID] [--workflow K] [--root PATH] [--json]'
              opts.on('--status S', String) { |v| options[:filters][:status] = v }
              opts.on('--label L', String) { |v| options[:filters][:label] = v }
              opts.on('--priority N', Integer) { |v| options[:filters][:priority] = v }
              opts.on('--parent ID', String) { |v| options[:filters][:parent] = v }
              opts.on('--workflow K', String) { |v| options[:filters][:workflow] = v }
              opts.on('--root PATH', String) { |v| options[:root] = v }
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
