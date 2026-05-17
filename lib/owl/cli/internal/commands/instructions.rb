# frozen_string_literal: true

require 'optparse'

require_relative '../../../instructions/api'
require_relative '../../../result'
require_relative '../../../steps/api'
require_relative '../../../tasks/api'
require_relative '../../../workflows/api'
require_relative '../json_printer'
require_relative 'task_support'

module Owl
  module Cli
    module Internal
      module Commands
        module Instructions
          module_function

          def run(argv:, stdout:, stderr:, cwd:, env: ENV.to_h) # rubocop:disable Lint/UnusedMethodArgument
            options, positional = parse_options(argv)
            root = TaskSupport.resolve_root(options[:root], cwd, stderr: stderr)
            return root if root.is_a?(Integer)

            payload = compute_payload(root: root, positional: positional, step_id_option: options[:step_id])
            return JsonPrinter.failure(stderr, **TaskSupport.error_payload(payload)) if payload.is_a?(Owl::Result::Err)

            JsonPrinter.success(stdout, payload)
          rescue OptionParser::ParseError => e
            JsonPrinter.failure(stderr, code: :invalid_arguments, message: e.message)
          end

          def compute_payload(root:, positional:, step_id_option:)
            task_id = positional.first || resolve_current_task_id(root: root)
            return task_id if task_id.is_a?(Owl::Result::Err)

            step_id = pick_step_id(root: root, task_id: task_id, explicit: step_id_option)
            return step_id if step_id.is_a?(Owl::Result::Err)

            invocation_result = Owl::Steps::Api.invocation(root: root, task_id: task_id, step_id: step_id)
            return invocation_result if invocation_result.err?

            invocation = invocation_result.value
            skill_result = lookup_skill(root: root, invocation: invocation, task_id: task_id, step_id: step_id)
            return skill_result if skill_result.is_a?(Owl::Result::Err)

            build_payload(invocation, skill_result)
          end

          def pick_step_id(root:, task_id:, explicit:)
            return explicit if explicit

            ready_result = Owl::Workflows::Api.ready_steps(root: root, task_id: task_id)
            return ready_result if ready_result.err?

            first = ready_result.value[:ready].first
            return first[:id] if first

            Owl::Result.err(
              code: :no_ready_steps,
              message: "Task '#{task_id}' has no ready steps.",
              details: { task_id: task_id.to_s }
            )
          end

          def lookup_skill(root:, invocation:, task_id:, step_id:)
            skill_id = invocation.dig(:step, :skill)
            unless skill_id
              return Owl::Result.err(
                code: :step_skill_missing,
                message: "Step '#{step_id}' does not declare a skill id in the workflow definition.",
                details: { task_id: task_id.to_s, step_id: step_id.to_s }
              )
            end

            result = Owl::Instructions::Api.read_skill(root: root, skill_id: skill_id)
            result.err? ? result : result.value
          end

          def resolve_current_task_id(root:)
            current = Owl::Tasks::Api.current(root: root)
            return current if current.err?

            current.value[:task_id]
          end

          def build_payload(invocation, skill_payload)
            task = invocation[:task]
            step = invocation[:step]
            {
              ok: true,
              task: {
                id: task[:id],
                title: task[:title],
                workflow_key: task[:workflow_key],
                kind: task[:kind]
              },
              step: {
                id: step[:id],
                status: step[:status],
                requires: step[:requires],
                creates: step[:creates]
              },
              skill: skill_payload[:skill],
              invocation: invocation,
              summary: skill_payload[:summary]
            }
          end

          def parse_options(argv)
            options = { root: nil, step_id: nil }
            parser = OptionParser.new do |opts|
              opts.banner = 'Usage: owl instructions [TASK-ID] [--step-id STEP] [--root PATH] [--json]'
              opts.on('--root PATH', String) { |v| options[:root] = v }
              opts.on('--step-id STEP', String) { |v| options[:step_id] = v }
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
