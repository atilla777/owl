# frozen_string_literal: true

require 'optparse'

require_relative '../../../tasks/api'
require_relative '../json_printer'
require_relative 'task_support'

module Owl
  module Cli
    module Internal
      module Commands
        module TaskClaim
          module_function

          def run(argv:, stdout:, stderr:, cwd:, env: ENV.to_h) # rubocop:disable Lint/UnusedMethodArgument
            options, positional = parse_options(argv)

            root = TaskSupport.resolve_root(options[:root], cwd, stderr: stderr)
            return root if root.is_a?(Integer)

            result = Owl::Tasks::Api.claim(
              root: root,
              task_id: positional.first,
              next_: options[:next],
              ttl: options[:ttl],
              label: options[:label],
              steal: options[:steal]
            )
            return JsonPrinter.failure(stderr, **TaskSupport.error_payload(result)) if result.err?

            payload = {
              ok: true,
              task_id: result.value[:task_id],
              token: result.value[:token],
              expires_at: result.value[:expires_at],
              stole_from: result.value[:stole_from],
              ready_step_ids: result.value[:ready_step_ids]
            }
            thread_takeover_hint(payload: payload, result: result, stderr: stderr)
            JsonPrinter.success(stdout, payload)
          rescue OptionParser::ParseError => e
            JsonPrinter.failure(stderr, code: :invalid_arguments, message: e.message)
          end

          # Additive takeover hint: present only when a --steal displaced a
          # session that left a step running (see ClaimService#takeover_hint).
          def thread_takeover_hint(payload:, result:, stderr:)
            return unless result.value[:hint]

            payload[:running_step] = result.value[:running_step]
            payload[:hint] = result.value[:hint]
            stderr.puts(result.value[:hint])
          end

          def parse_options(argv)
            options = { root: nil, next: false, ttl: nil, label: nil, steal: false }
            parser = OptionParser.new do |opts|
              opts.banner = 'Usage: owl task claim [TASK-ID] [--next] [--ttl N] [--label S] ' \
                            '[--steal] [--root PATH] [--json]'
              opts.on('--next', 'Auto-select the best runnable unclaimed task') { options[:next] = true }
              opts.on('--ttl N', Integer) { |v| options[:ttl] = v }
              opts.on('--label S', String) { |v| options[:label] = v }
              opts.on('--steal', 'Forcibly take over an existing claim') { options[:steal] = true }
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
