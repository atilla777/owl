# frozen_string_literal: true

require 'optparse'

require_relative '../../../workflows/api'
require_relative '../json_printer'
require_relative 'task_support'

module Owl
  module Cli
    module Internal
      module Commands
        module WorkflowShow
          module_function

          def run(argv:, stdout:, stderr:, cwd:, env: ENV.to_h) # rubocop:disable Lint/UnusedMethodArgument
            options, positional = parse_options(argv)
            id = positional[0]
            unless id
              return JsonPrinter.failure(stderr, code: :invalid_arguments,
                                                 message: 'ID positional argument is required.')
            end

            root = TaskSupport.resolve_root(options[:root], cwd, stderr: stderr)
            return root if root.is_a?(Integer)

            result = Owl::Workflows::Api.find(root: root, key: id)
            return JsonPrinter.failure(stderr, **TaskSupport.error_payload(result)) if result.err?

            entry = result.value[:entry]
            source = result.value[:source]

            JsonPrinter.success(stdout, {
                                  ok: true,
                                  id: entry[:key],
                                  source: entry[:source],
                                  source_present: source[:present],
                                  source_path: source[:source_path],
                                  registry_entry: {
                                    enabled: entry[:enabled],
                                    title: entry[:title],
                                    aliases: entry[:aliases],
                                    priority: entry[:priority],
                                    version: entry[:version]
                                  },
                                  definition: source[:body]
                                })
          rescue OptionParser::ParseError => e
            JsonPrinter.failure(stderr, code: :invalid_arguments, message: e.message)
          end

          def parse_options(argv)
            options = { root: nil }
            parser = OptionParser.new do |opts|
              opts.banner = 'Usage: owl workflow show ID [--root PATH] [--json]'
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
