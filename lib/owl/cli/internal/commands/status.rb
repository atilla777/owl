# frozen_string_literal: true

require 'optparse'

require_relative '../../../result'
require_relative '../../../tasks/api'
require_relative '../../../workflows/api'
require_relative '../json_printer'
require_relative 'task_support'

module Owl
  module Cli
    module Internal
      module Commands
        module Status
          COMPOSITE_KIND = 'composite_task'
          DONE_STATUSES = %w[done skipped].freeze
          BLOCKER_STATUSES = %w[blocked failed].freeze
          DEFAULT_TASK_STATUS = 'todo'

          module_function

          def run(argv:, stdout:, stderr:, cwd:, env: ENV.to_h) # rubocop:disable Lint/UnusedMethodArgument
            options, positional = parse_options(argv)
            root = TaskSupport.resolve_root(options[:root], cwd, stderr: stderr)
            return root if root.is_a?(Integer)

            task_id = positional.first || resolve_current_task_id(root: root)
            return JsonPrinter.failure(stderr, **TaskSupport.error_payload(task_id)) if task_id.is_a?(Owl::Result::Err)

            inspect_result = Owl::Tasks::Api.inspect(root: root, task_id: task_id)
            return JsonPrinter.failure(stderr, **TaskSupport.error_payload(inspect_result)) if inspect_result.err?

            payload = inspect_result.value[:payload]
            ready_ids = ready_step_ids(root: root, task_id: task_id)

            body = build_payload(root: root, task_id: task_id, payload: payload, ready_ids: ready_ids)
            JsonPrinter.success(stdout, body)
          rescue OptionParser::ParseError => e
            JsonPrinter.failure(stderr, code: :invalid_arguments, message: e.message)
          end

          def resolve_current_task_id(root:)
            current = Owl::Tasks::Api.current(root: root)
            return current if current.err?

            current.value[:task_id]
          end

          def ready_step_ids(root:, task_id:)
            ready = Owl::Workflows::Api.ready_steps(root: root, task_id: task_id)
            return [] if ready.err?

            ready.value[:ready].map { |entry| entry[:id].to_s }
          end

          def build_payload(root:, task_id:, payload:, ready_ids:)
            steps = Array(payload['steps'])
            steps_view = steps.map { |step| step_view(step, ready_ids: ready_ids) }
            progress = progress_view(steps)
            blockers = steps_view
                       .select { |s| BLOCKER_STATUSES.include?(s[:status]) }
                       .map { |s| { id: s[:id], status: s[:status] } }

            body = {
              ok: true,
              task: task_view(task_id: task_id, payload: payload),
              steps: steps_view,
              progress: progress,
              blockers: blockers
            }

            body[:children] = children_view(root: root, parent_id: task_id) if payload['kind'].to_s == COMPOSITE_KIND

            body
          end

          def task_view(task_id:, payload:)
            {
              id: task_id.to_s,
              title: payload['title'],
              workflow_key: payload.dig('workflow', 'key'),
              kind: payload['kind'],
              parent_id: payload['parent_id']
            }
          end

          def step_view(step, ready_ids:)
            step ||= {}
            id = (step['id'] || step[:id]).to_s
            status = (step['status'] || step[:status] || 'pending').to_s
            {
              id: id,
              status: status,
              skill: step['skill'] || step[:skill],
              ready: ready_ids.include?(id)
            }
          end

          def progress_view(steps)
            total = steps.size
            done = steps.count do |step|
              status = (step.is_a?(Hash) ? (step['status'] || step[:status]) : nil).to_s
              DONE_STATUSES.include?(status)
            end
            pct = total.zero? ? 0.0 : ((done * 100.0) / total).round(1)
            { done: done, total: total, pct: pct }
          end

          def children_view(root:, parent_id:)
            list_result = Owl::Tasks::Api.list(root: root)
            return [] if list_result.err?

            tasks = list_result.value[:tasks]
            children = tasks.select do |entry|
              entry.is_a?(Hash) && entry['parent_id'].to_s == parent_id.to_s
            end

            children.map { |child| child_view(root: root, child_summary: child) }
          end

          def child_view(root:, child_summary:)
            child_id = child_summary['id'].to_s
            inspect_result = Owl::Tasks::Api.inspect(root: root, task_id: child_id)
            if inspect_result.err?
              return {
                id: child_id,
                status: child_summary['status'] || DEFAULT_TASK_STATUS,
                progress: { done: 0, total: 0, pct: 0.0 }
              }
            end

            payload = inspect_result.value[:payload]
            {
              id: child_id,
              status: payload['status'] || child_summary['status'] || DEFAULT_TASK_STATUS,
              progress: progress_view(Array(payload['steps']))
            }
          end

          def parse_options(argv)
            options = { root: nil }
            parser = OptionParser.new do |opts|
              opts.banner = 'Usage: owl status [TASK-ID] [--root PATH] [--json]'
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
