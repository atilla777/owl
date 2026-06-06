# frozen_string_literal: true

require 'optparse'

require_relative '../../../workflows/api'
require_relative '../json_printer'
require_relative 'task_support'

module Owl
  module Cli
    module Internal
      module Commands
        # `owl workflow source show ID` — return the raw workflow.yaml body, so
        # an agent can round-trip edit it (read → modify → `workflow new --body -
        # --force`) without reading .owl/ files directly.
        module WorkflowSource
          module_function

          def run(argv:, stdout:, stderr:, cwd:, env: ENV.to_h) # rubocop:disable Lint/UnusedMethodArgument
            sub = argv.first
            return show(argv: argv.drop(1), stdout: stdout, stderr: stderr, cwd: cwd) if sub == 'show'

            JsonPrinter.failure(stderr, code: :unknown_command, message: "Unknown command: 'workflow source #{sub}'.")
          end

          def show(argv:, stdout:, stderr:, cwd:)
            options = parse_options(argv)
            id = options[:id] || argv.shift
            return JsonPrinter.failure(stderr, code: :invalid_arguments, message: 'ID is required.') unless id

            root = TaskSupport.resolve_root(options[:root], cwd, stderr: stderr)
            return root if root.is_a?(Integer)

            result = Owl::Workflows::Api.source_show(root: root, id: id)
            return JsonPrinter.failure(stderr, **TaskSupport.error_payload(result)) if result.err?

            JsonPrinter.success(stdout, { ok: true }.merge(result.value))
          rescue OptionParser::ParseError => e
            JsonPrinter.failure(stderr, code: :invalid_arguments, message: e.message)
          end

          def parse_options(argv)
            options = { id: nil, root: nil }
            parser = OptionParser.new do |opts|
              opts.banner = 'Usage: owl workflow source show ID [--root PATH] [--json]'
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
