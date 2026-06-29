# frozen_string_literal: true

require 'optparse'

require_relative '../../../tasks/api'
require_relative '../json_printer'
require_relative 'task_support'

module Owl
  module Cli
    module Internal
      module Commands
        # `owl doctor [--fix]` — lifecycle-drift reconciler. Report-only by
        # default: lists tasks whose workflow is terminally complete but whose
        # `status` is still `open`/`in_progress` (detected read-only via
        # `Tasks::Api.lifecycle_drift`). With `--fix`, promotes each such task to
        # `done` through the existing `Tasks::Api.set_status` writer (per-task
        # lock + schema + index rebuild), idempotently.
        module Doctor
          module_function

          def run(argv:, stdout:, stderr:, cwd:, env: ENV.to_h) # rubocop:disable Lint/UnusedMethodArgument
            options = parse_options(argv)

            root = TaskSupport.resolve_root(options[:root], cwd, stderr: stderr)
            return root if root.is_a?(Integer)

            drift_result = Owl::Tasks::Api.lifecycle_drift(root: root)
            return JsonPrinter.failure(stderr, **TaskSupport.error_payload(drift_result)) if drift_result.err?

            drifted = Array(drift_result.value[:drifted])
            return report(stdout, drifted) unless options[:fix]

            fix(stdout: stdout, stderr: stderr, root: root, drifted: drifted)
          rescue OptionParser::ParseError => e
            JsonPrinter.failure(stderr, code: :invalid_arguments, message: e.message)
          end

          def report(stdout, drifted)
            JsonPrinter.success(stdout, { ok: true, drifted: drifted, fixed: [] })
          end

          def fix(stdout:, stderr:, root:, drifted:)
            fixed = []
            drifted.each do |entry|
              result = Owl::Tasks::Api.set_status(root: root, task_id: entry[:task_id], status: 'done')
              return JsonPrinter.failure(stderr, **TaskSupport.error_payload(result)) if result.err?

              fixed << { task_id: entry[:task_id], from: entry[:status], to: 'done' }
            end

            JsonPrinter.success(stdout, { ok: true, drifted: drifted, fixed: fixed })
          end

          def parse_options(argv)
            options = { root: nil, fix: false }
            parser = OptionParser.new do |opts|
              opts.banner = 'Usage: owl doctor [--fix] [--root PATH] [--json]'
              opts.on('--fix', 'Reconcile detected drift (open|in_progress -> done)') { options[:fix] = true }
              opts.on('--root PATH', String) { |v| options[:root] = v }
              opts.on('--json', 'Force JSON output (default)') { options[:json] = true }
            end
            parser.parse(argv)
            options
          end
        end
      end
    end
  end
end
