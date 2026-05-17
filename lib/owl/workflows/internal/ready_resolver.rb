# frozen_string_literal: true

require_relative '../../steps/internal/statuses'

module Owl
  module Workflows
    module Internal
      module ReadyResolver
        module_function

        def resolve(graph:, task_steps:)
          status_map = build_status_map(task_steps)
          step_map = build_step_map(task_steps)

          graph[:order].each_with_object([]) do |id, ready|
            current = status_map[id] || Owl::Steps::Internal::Statuses::DEFAULT
            next unless current == 'pending'

            requires = graph[:nodes][id][:requires]
            next unless requires.all? do |dep|
              Owl::Steps::Internal::Statuses.completes_for_unblocking?(status_map[dep])
            end

            ready << ready_entry(id, step_map[id])
          end
        end

        def build_status_map(task_steps)
          Array(task_steps).each_with_object({}) do |step, memo|
            next unless step.is_a?(Hash)

            id = step['id'] || step[:id]
            next if id.nil?

            status = step['status'] || step[:status]
            memo[id.to_s] = (status || Owl::Steps::Internal::Statuses::DEFAULT).to_s
          end
        end

        def build_step_map(task_steps)
          Array(task_steps).each_with_object({}) do |step, memo|
            next unless step.is_a?(Hash)

            id = step['id'] || step[:id]
            memo[id.to_s] = step unless id.nil?
          end
        end

        def ready_entry(id, step)
          step ||= {}
          requires = step['requires'] || step[:requires] || []

          {
            id: id,
            kind: step['kind'] || step[:kind],
            requires: Array(requires).map(&:to_s),
            status: 'ready'
          }
        end
      end
    end
  end
end
