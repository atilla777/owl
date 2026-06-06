# frozen_string_literal: true

require 'optparse'

require_relative '../../../workflows/api'
require_relative '../json_printer'
require_relative 'task_support'

module Owl
  module Cli
    module Internal
      module Commands
        # `owl workflow context <show|set> ID STEP [--variant V]` — read/write a
        # step's context-file body, mirroring `artifact-type template`. `set`
        # refuses managed (Owl-shipped) workflows.
        module WorkflowContext
          module_function

          def run(argv:, stdout:, stderr:, cwd:, env: ENV.to_h) # rubocop:disable Lint/UnusedMethodArgument
            sub = argv.first
            rest = argv.drop(1)
            case sub
            when 'show' then show(argv: rest, stdout: stdout, stderr: stderr, cwd: cwd)
            when 'set'  then set(argv: rest, stdout: stdout, stderr: stderr, cwd: cwd)
            else
              JsonPrinter.failure(stderr, code: :unknown_command,
                                          message: "Unknown command: 'workflow context #{sub}'.")
            end
          end

          def show(argv:, stdout:, stderr:, cwd:)
            options, ids, root = prepare(argv, cwd, stderr)
            return ids if ids.is_a?(Integer)

            result = Owl::Workflows::Api.context_show(
              root: root, id: ids[0], step_id: ids[1], variant: options[:variant]
            )
            return JsonPrinter.failure(stderr, **TaskSupport.error_payload(result)) if result.err?

            JsonPrinter.success(stdout, { ok: true }.merge(result.value))
          rescue OptionParser::ParseError => e
            JsonPrinter.failure(stderr, code: :invalid_arguments, message: e.message)
          end

          def set(argv:, stdout:, stderr:, cwd:)
            options, ids, root = prepare(argv, cwd, stderr)
            return ids if ids.is_a?(Integer)

            body = read_body(options[:body], stderr: stderr)
            return body if body.is_a?(Integer)
            if body.nil?
              return JsonPrinter.failure(stderr, code: :invalid_arguments, message: '--body is required for set.')
            end

            result = Owl::Workflows::Api.context_set(
              root: root, id: ids[0], step_id: ids[1], body: body, variant: options[:variant]
            )
            return JsonPrinter.failure(stderr, **TaskSupport.error_payload(result)) if result.err?

            JsonPrinter.success(stdout, { ok: true }.merge(result.value))
          rescue OptionParser::ParseError => e
            JsonPrinter.failure(stderr, code: :invalid_arguments, message: e.message)
          end

          def prepare(argv, cwd, stderr)
            options = parse_options(argv)
            root = TaskSupport.resolve_root(options[:root], cwd, stderr: stderr)
            return [options, root, nil] if root.is_a?(Integer)

            id = options[:id] || argv.shift
            step_id = options[:step] || argv.shift
            unless id && step_id
              return [options,
                      JsonPrinter.failure(stderr, code: :invalid_arguments, message: 'ID and STEP are required.'),
                      root]
            end

            [options, [id, step_id], root]
          end

          def parse_options(argv)
            options = { id: nil, step: nil, variant: nil, body: nil, root: nil }
            parser = OptionParser.new do |opts|
              opts.banner = 'Usage: owl workflow context <show|set> ID STEP ' \
                            '[--variant V] [--body -] [--root PATH] [--json]'
              opts.on('--variant V', String) { |v| options[:variant] = v }
              opts.on('--body BODY', String) { |v| options[:body] = v }
              opts.on('--root PATH', String) { |v| options[:root] = v }
              opts.on('--json', 'Force JSON output (default)') { options[:json] = true }
            end
            parser.parse!(argv)
            options
          end

          def read_body(body_opt, stderr:)
            return nil if body_opt.nil?

            return $stdin.read if body_opt == '-'

            body_opt
          rescue StandardError => e
            JsonPrinter.failure(stderr, code: :invalid_arguments, message: "Failed to read body: #{e.message}")
          end
        end
      end
    end
  end
end
