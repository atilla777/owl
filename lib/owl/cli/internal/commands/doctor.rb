# frozen_string_literal: true

require 'optparse'

require_relative '../../../tasks/api'
require_relative '../json_printer'
require_relative 'task_support'

module Owl
  module Cli
    module Internal
      module Commands
        # `owl doctor [--fix]` — repo health reconciler. Report-only by default;
        # scans three independent drift classes and returns them side by side:
        #
        # - `drifted`      lifecycle: workflow terminally complete but task
        #                  `status` still `open`/`in_progress`.
        # - `index_drift`  `tasks/index.yaml` diverged from the per-task
        #                  `task.yaml` files (missing / stale / field mismatch).
        # - `stale_steps`  a `running` step orphaned by a dead session (task
        #                  holds an expired claim lease). Report-only — recovery
        #                  is `owl task adopt`, never auto-mutated here.
        # - `orphans`      a task whose `parent_id` names a missing task (a
        #                  parent deleted before delete grew its recursive
        #                  guard). Report-only — a human re-parents or deletes.
        # - `dangling_deps` a task whose `blocked_by` references missing tasks.
        #                  Report-only — scrub with `owl task dep remove`.
        #
        # With `--fix`, the two safe/deterministic classes are reconciled:
        # lifecycle via `Tasks::Api.set_status` (→ `fixed`) and index via
        # `Tasks::Api.rebuild_index` (→ `index_rebuilt`). `stale_steps`,
        # `orphans`, and `dangling_deps` stay report-only — each needs human
        # judgement (re-parent vs delete, keep vs drop) that a mechanical fix
        # cannot safely make.
        module Doctor
          module_function

          def run(argv:, stdout:, stderr:, cwd:, env: ENV.to_h) # rubocop:disable Lint/UnusedMethodArgument
            options = parse_options(argv)

            root = TaskSupport.resolve_root(options[:root], cwd, stderr: stderr)
            return root if root.is_a?(Integer)

            scan = collect(root: root)
            return JsonPrinter.failure(stderr, **TaskSupport.error_payload(scan[:error])) if scan[:error]

            return report(stdout, scan) unless options[:fix]

            fix(stdout: stdout, stderr: stderr, root: root, scan: scan)
          rescue OptionParser::ParseError => e
            JsonPrinter.failure(stderr, code: :invalid_arguments, message: e.message)
          end

          # Run all read-only scanners, short-circuiting on the first Err.
          def collect(root:)
            lifecycle = Owl::Tasks::Api.lifecycle_drift(root: root)
            return { error: lifecycle } if lifecycle.err?

            index = Owl::Tasks::Api.index_drift(root: root)
            return { error: index } if index.err?

            stale = Owl::Tasks::Api.stale_steps(root: root)
            return { error: stale } if stale.err?

            integrity = Owl::Tasks::Api.integrity_drift(root: root)
            return { error: integrity } if integrity.err?

            {
              drifted: Array(lifecycle.value[:drifted]),
              index_drift: Array(index.value[:index_drift]),
              stale_steps: Array(stale.value[:stale_steps]),
              orphans: Array(integrity.value[:orphans]),
              dangling_deps: Array(integrity.value[:dangling_deps])
            }
          end

          def report(stdout, scan)
            JsonPrinter.success(stdout, base_payload(scan).merge(fixed: [], index_rebuilt: false))
          end

          def fix(stdout:, stderr:, root:, scan:)
            fixed = []
            scan[:drifted].each do |entry|
              result = Owl::Tasks::Api.set_status(root: root, task_id: entry[:task_id], status: 'done')
              return JsonPrinter.failure(stderr, **TaskSupport.error_payload(result)) if result.err?

              fixed << { task_id: entry[:task_id], from: entry[:status], to: 'done' }
            end

            index_rebuilt = false
            unless scan[:index_drift].empty?
              rebuilt = Owl::Tasks::Api.rebuild_index(root: root)
              return JsonPrinter.failure(stderr, **TaskSupport.error_payload(rebuilt)) if rebuilt.err?

              index_rebuilt = true
            end

            JsonPrinter.success(stdout, base_payload(scan).merge(fixed: fixed, index_rebuilt: index_rebuilt))
          end

          def base_payload(scan)
            {
              ok: true,
              drifted: scan[:drifted],
              index_drift: scan[:index_drift],
              stale_steps: scan[:stale_steps],
              orphans: scan[:orphans],
              dangling_deps: scan[:dangling_deps]
            }
          end

          def parse_options(argv)
            options = { root: nil, fix: false }
            parser = OptionParser.new do |opts|
              opts.banner = 'Usage: owl doctor [--fix] [--root PATH] [--json]'
              opts.on('--fix', 'Reconcile lifecycle + index drift (stale steps stay report-only)') do
                options[:fix] = true
              end
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
