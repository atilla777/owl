# frozen_string_literal: true

require 'optparse'

require_relative '../json_printer'
require_relative 'overview_data'
require_relative 'overview_renderer'
require_relative 'task_support'

module Owl
  module Cli
    module Internal
      module Commands
        # `owl overview [TASK-ID] [--all] [--compact] [--json]` — render an ASCII
        # task tree (hierarchy, status, dependencies, current task), or the
        # structured view-model under `--json`. Thin CLI orchestration over the
        # existing Api layer (see OverviewData); no state mutation, no lease.
        module Overview
          module_function

          def run(argv:, stdout:, stderr:, cwd:, env: ENV.to_h) # rubocop:disable Lint/UnusedMethodArgument
            options, positional = parse_options(argv)
            root = TaskSupport.resolve_root(options[:root], cwd, stderr: stderr)
            return root if root.is_a?(Integer)

            data = OverviewData.build(root: root, task_id: positional.first, all: options[:all])
            return JsonPrinter.failure(stderr, **TaskSupport.error_payload(data)) if data.err?

            return print_json(stdout: stdout, payload: data.value) if options[:json]

            stdout.puts(OverviewRenderer.render(data.value, compact: options[:compact]))
            0
          rescue OptionParser::ParseError => e
            JsonPrinter.failure(stderr, code: :invalid_arguments, message: e.message)
          end

          def print_json(stdout:, payload:)
            JsonPrinter.success(stdout, {
                                  ok: true,
                                  tree: payload[:tree],
                                  current_task_id: payload[:current_task_id],
                                  warnings: payload[:warnings]
                                })
          end

          def parse_options(argv)
            options = { root: nil, all: false, compact: false, json: false }
            parser = OptionParser.new do |opts|
              opts.banner = 'Usage: owl overview [TASK-ID] [--all] [--compact] [--root PATH] [--json]'
              opts.on('--root PATH', String) { |v| options[:root] = v }
              opts.on('--all', 'Include archived/abandoned tasks') { options[:all] = true }
              opts.on('--compact', 'Compact node (marker, id, title only)') { options[:compact] = true }
              opts.on('--json', 'Force structured JSON output') { options[:json] = true }
            end
            positional = parser.parse(argv)
            [options, positional]
          end
        end
      end
    end
  end
end
