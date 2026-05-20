# frozen_string_literal: true

require_relative '../../../result'
require_relative '../../../tasks/api'
require_relative '../../../workflows/api'
require_relative 'status'

module Owl
  module Cli
    module Internal
      module Commands
        module WorkflowDiagramData
          DONE_STATUSES = %w[done skipped].freeze
          BLOCKED_STATUSES = %w[blocked failed].freeze

          module_function

          def build_live(root:, task_id:)
            inspect_result = Owl::Tasks::Api.inspect(root: root, task_id: task_id)
            return inspect_result if inspect_result.err?

            payload = inspect_result.value[:payload]
            workflow_key = payload.dig('workflow', 'key')
            return missing_workflow_err(task_id) unless workflow_key

            workflow_find = Owl::Workflows::Api.find(root: root, key: workflow_key)
            return workflow_find if workflow_find.err?

            workflow_steps = workflow_steps_for(workflow_find.value)
            ready_ids = Status.ready_step_ids(root: root, task_id: task_id)
            step_variants = payload['step_variants'].is_a?(Hash) ? payload['step_variants'] : {}
            steps_view = live_steps_view(
              payload: payload,
              workflow_steps: workflow_steps,
              ready_ids: ready_ids,
              step_variants: step_variants
            )

            Owl::Result.ok(
              mode: :live,
              task: { id: task_id.to_s, title: payload['title'], workflow_key: workflow_key },
              steps: steps_view,
              progress: Status.progress_view(payload['steps'] || []),
              blockers: collect_blockers(steps_view)
            )
          end

          def missing_workflow_err(task_id)
            Owl::Result.err(
              code: :task_workflow_missing,
              message: "Task '#{task_id}' has no workflow key in task.yaml.",
              details: { task_id: task_id.to_s }
            )
          end

          def workflow_steps_for(find_value)
            definition = find_value[:source][:body]
            definition && definition['steps'] ? Array(definition['steps']) : []
          end

          def live_steps_view(payload:, workflow_steps:, ready_ids:, step_variants: {})
            steps = build_step_views(
              task_steps: payload['steps'] || [],
              workflow_steps: workflow_steps,
              ready_ids: ready_ids,
              step_variants: step_variants
            )
            current_id = ready_ids.first
            steps.each { |step| step[:current] = (step[:id] == current_id) }
            steps
          end

          def collect_blockers(steps_view)
            steps_view
              .select { |s| BLOCKED_STATUSES.include?(s[:status]) }
              .map { |s| { id: s[:id], status: s[:status] } }
          end

          def build_abstract(root:, workflow_key:)
            workflow_find = Owl::Workflows::Api.find(root: root, key: workflow_key)
            return workflow_find if workflow_find.err?

            definition = workflow_find.value[:source][:body]
            workflow_steps = definition && definition['steps'] ? Array(definition['steps']) : []

            steps_view = workflow_steps.map do |ws|
              base_step_view(ws).merge(
                status: 'pending',
                ready: false,
                current: false
              )
            end

            Owl::Result.ok(
              mode: :abstract,
              workflow_key: workflow_key.to_s,
              steps: steps_view
            )
          end

          def build_step_views(task_steps:, workflow_steps:, ready_ids:, step_variants: {})
            workflow_by_id = workflow_steps.to_h { |ws| [ws['id'].to_s, ws] }
            order = workflow_steps.map { |ws| ws['id'].to_s }
            task_by_id = task_steps.each_with_object({}) do |ts, h|
              id = (ts['id'] || ts[:id]).to_s
              h[id] = ts
            end

            order.map do |id|
              ws = workflow_by_id[id] || {}
              ts = task_by_id[id] || {}
              status = (ts['status'] || ts[:status] || 'pending').to_s
              chosen = (step_variants[id] || ws['default_variant'])&.to_s
              chosen = nil if chosen.nil? || chosen.empty? || !ws['variants'].is_a?(Hash)
              base_step_view(ws).merge(
                status: status,
                ready: ready_ids.include?(id),
                current: false,
                chosen_variant: chosen
              )
            end
          end

          def base_step_view(ws)
            {
              id: ws['id'].to_s,
              optional: ws['optional'] == true,
              requires: Array(ws['requires']).map(&:to_s),
              creates: Array(ws['creates']).map(&:to_s),
              variants: variant_keys(ws),
              default_variant: ws['default_variant']
            }
          end

          def variant_keys(ws)
            variants = ws['variants']
            return [] unless variants.is_a?(Hash)

            variants.keys.map(&:to_s)
          end
        end
      end
    end
  end
end
