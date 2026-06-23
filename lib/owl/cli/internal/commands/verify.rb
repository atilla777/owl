# frozen_string_literal: true

require 'optparse'

require_relative '../../../verification/api'
require_relative '../json_printer'
require_relative 'task_support'

module Owl
  module Cli
    module Internal
      module Commands
        # `owl verify TASK-ID` — run the objective verification command for a
        # task without completing any step (a convenience pre-check). The same
        # engine backs the `step complete` gate. Reports `gate_active: false`
        # with a warning when no command is configured (fail-open).
        module Verify
          module_function

          def run(argv:, stdout:, stderr:, cwd:, env: ENV.to_h) # rubocop:disable Lint/UnusedMethodArgument
            options, positional = parse_options(argv)
            task_id = positional.first
            unless task_id
              return JsonPrinter.failure(
                stderr, code: :invalid_arguments, message: 'TASK-ID positional argument is required.'
              )
            end

            root = TaskSupport.resolve_root(options[:root], cwd, stderr: stderr)
            return root if root.is_a?(Integer)

            command = Owl::Verification::Api.configured_command(root: root)
            return inactive(stdout, stderr, task_id) if command.nil?

            run_command(stdout: stdout, stderr: stderr, root: root, task_id: task_id)
          rescue OptionParser::ParseError => e
            JsonPrinter.failure(stderr, code: :invalid_arguments, message: e.message)
          end

          def run_command(stdout:, stderr:, root:, task_id:)
            result = Owl::Verification::Api.run(root: root, task_id: task_id)
            return JsonPrinter.failure(stderr, **TaskSupport.error_payload(result)) if result.err?

            JsonPrinter.success(stdout, {
                                  ok: true, task_id: task_id, gate_active: true,
                                  status: result.value[:status], exit_code: result.value[:exit_code],
                                  command: result.value[:command], timed_out: result.value[:timed_out]
                                })
          end

          def inactive(stdout, stderr, task_id)
            stderr.puts(
              "WARNING: verification_gate_inactive: no settings.verification.command configured for #{task_id}."
            )
            JsonPrinter.success(stdout, {
                                  ok: true, task_id: task_id, gate_active: false,
                                  status: nil, exit_code: nil, command: nil
                                })
          end

          def parse_options(argv)
            options = { root: nil }
            parser = OptionParser.new do |opts|
              opts.banner = 'Usage: owl verify TASK-ID [--root PATH] [--json]'
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
