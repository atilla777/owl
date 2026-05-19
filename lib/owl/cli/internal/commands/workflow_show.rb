# frozen_string_literal: true

require 'optparse'

require_relative '../../../workflows/api'
require_relative '../json_printer'
require_relative 'task_support'
require_relative 'workflow_diagram_data'
require_relative 'workflow_diagram_renderer'

module Owl
  module Cli
    module Internal
      module Commands
        module WorkflowShow
          TASK_ID_PATTERN = /\A[A-Z]+-\d+\z/i

          module_function

          def run(argv:, stdout:, stderr:, cwd:, env: ENV.to_h) # rubocop:disable Lint/UnusedMethodArgument
            options, positional = parse_options(argv)
            positional_arg = positional[0]

            if options[:workflow] && positional_arg
              msg = 'Pass either a TASK-ID positional or --workflow KEY, not both.'
              return JsonPrinter.failure(stderr, code: :invalid_arguments, message: msg)
            end

            if positional_arg.nil? && options[:workflow].nil?
              return JsonPrinter.failure(stderr, code: :invalid_arguments,
                                                 message: 'TASK-ID positional or --workflow KEY is required.')
            end

            root = TaskSupport.resolve_root(options[:root], cwd, stderr: stderr)
            return root if root.is_a?(Integer)

            if positional_arg && TASK_ID_PATTERN.match?(positional_arg.to_s)
              return run_live(root: root, task_id: positional_arg.to_s, json: options[:json], stdout: stdout,
                              stderr: stderr)
            end

            if options[:workflow]
              return run_abstract(root: root, workflow_key: options[:workflow], json: options[:json],
                                  stdout: stdout, stderr: stderr)
            end

            run_legacy_show(root: root, key: positional_arg.to_s, stdout: stdout, stderr: stderr)
          rescue OptionParser::ParseError => e
            JsonPrinter.failure(stderr, code: :invalid_arguments, message: e.message)
          end

          def run_live(root:, task_id:, json:, stdout:, stderr:)
            data = WorkflowDiagramData.build_live(root: root, task_id: task_id)
            return JsonPrinter.failure(stderr, **TaskSupport.error_payload(data)) if data.err?

            payload = data.value
            return print_live_json(stdout: stdout, payload: payload) if json

            stdout.puts(WorkflowDiagramRenderer.render(payload))
            0
          end

          def run_abstract(root:, workflow_key:, json:, stdout:, stderr:)
            data = WorkflowDiagramData.build_abstract(root: root, workflow_key: workflow_key)
            return JsonPrinter.failure(stderr, **TaskSupport.error_payload(data)) if data.err?

            payload = data.value
            return print_abstract_json(stdout: stdout, payload: payload) if json

            stdout.puts(WorkflowDiagramRenderer.render(payload))
            0
          end

          def run_legacy_show(root:, key:, stdout:, stderr:)
            result = Owl::Workflows::Api.find(root: root, key: key)
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
          end

          def print_live_json(stdout:, payload:)
            JsonPrinter.success(stdout, {
                                  ok: true,
                                  mode: 'live',
                                  task: payload[:task],
                                  steps: payload[:steps],
                                  progress: payload[:progress],
                                  blockers: payload[:blockers]
                                })
          end

          def print_abstract_json(stdout:, payload:)
            JsonPrinter.success(stdout, {
                                  ok: true,
                                  mode: 'abstract',
                                  workflow_key: payload[:workflow_key],
                                  steps: payload[:steps]
                                })
          end

          def parse_options(argv)
            options = { root: nil, workflow: nil, json: false }
            parser = OptionParser.new do |opts|
              opts.banner = 'Usage: owl workflow show TASK-ID | --workflow KEY | KEY [--root PATH] [--json]'
              opts.on('--root PATH', String) { |v| options[:root] = v }
              opts.on('--workflow KEY', String) { |v| options[:workflow] = v }
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
