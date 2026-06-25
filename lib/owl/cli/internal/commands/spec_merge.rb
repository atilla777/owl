# frozen_string_literal: true

require 'optparse'

require_relative '../../../specs/api'
require_relative '../json_printer'
require_relative 'task_support'

module Owl
  module Cli
    module Internal
      module Commands
        # `owl spec merge TASK-ID [--dry-run] [--json|--no-json]` — apply a
        # task's optional `spec_delta` into its domain spec (P4) and gate on
        # traceability (P5 `--strict`). A task with no spec_delta is a graceful
        # no-op (`reason: no_spec_delta`). The process exit code follows `ok`
        # (0 when ok, 1 when the trace gate fails), so `merge_docs` surfaces an
        # untraced/dangling spec as a non-zero exit.
        module SpecMerge
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

            result = Owl::Specs::Api.merge_task(root: root, task_id: task_id, dry_run: options[:dry_run])
            return JsonPrinter.failure(stderr, **TaskSupport.error_payload(result)) if result.err?

            emit(stdout, result.value, json: options[:json])
          rescue OptionParser::ParseError => e
            JsonPrinter.failure(stderr, code: :invalid_arguments, message: e.message)
          end

          def emit(stdout, value, json:)
            return emit_summary(stdout, value) unless json

            stdout.puts(JSON.generate(json_payload(value)))
            value[:ok] ? 0 : 1
          end

          def json_payload(value)
            {
              ok: value[:ok],
              applied: value[:applied],
              unchanged: value.dig(:merge, :unchanged),
              reason: value[:reason],
              domain: value[:domain],
              merge: value[:merge],
              trace: value[:trace]
            }
          end

          def emit_summary(stdout, value)
            if value[:reason] == 'no_spec_delta'
              stdout.puts('spec merge: no spec_delta artifact — nothing to merge (no-op).')
              return 0
            end

            stdout.puts("spec merge #{value[:domain]} (applied: #{value[:applied]})")
            print_merge(stdout, value[:merge])
            print_unchanged(stdout, value[:merge])
            print_trace(stdout, value[:trace])
            value[:ok] ? 0 : 1
          end

          def print_merge(stdout, merge)
            return unless merge.is_a?(Hash)

            counts = merge[:applied] || {}
            stdout.puts(
              format('  delta: added %<added>d  modified %<modified>d  removed %<removed>d',
                     added: counts[:added].to_i, modified: counts[:modified].to_i, removed: counts[:removed].to_i)
            )
          end

          def print_unchanged(stdout, merge)
            return unless merge.is_a?(Hash)

            counts = merge[:unchanged] || {}
            stdout.puts(
              format('  unchanged: added %<added>d  modified %<modified>d  removed %<removed>d',
                     added: counts[:added].to_i, modified: counts[:modified].to_i, removed: counts[:removed].to_i)
            )
          end

          def print_trace(stdout, trace)
            return unless trace.is_a?(Hash)

            stdout.puts("  trace: valid=#{trace[:valid]} untraced=#{Array(trace[:untraced]).length} " \
                        "dangling=#{Array(trace[:dangling]).length}")
          end

          def parse_options(argv)
            options = { root: nil, dry_run: false, json: true }
            parser = OptionParser.new do |opts|
              opts.banner = 'Usage: owl spec merge TASK-ID [--dry-run] [--root PATH] [--json|--no-json]'
              opts.on('--dry-run', 'Preview the merge + trace without writing') { options[:dry_run] = true }
              opts.on('--root PATH', String) { |v| options[:root] = v }
              opts.on('--[no-]json', 'Emit JSON (default) or a readable summary') { |v| options[:json] = v }
            end
            positional = parser.parse(argv)
            [options, positional]
          end
        end
      end
    end
  end
end
