# frozen_string_literal: true

require_relative '../../result'

module Owl
  module Workflows
    module Internal
      module GraphBuilder
        module_function

        def build(steps)
          collected = collect_nodes(Array(steps))
          return collected if collected.is_a?(Owl::Result::Err)

          ids, nodes = collected
          requires_err = validate_requires(nodes)
          return requires_err if requires_err

          cycle = detect_cycle(nodes)
          if cycle
            return Result.err(
              code: :workflow_cycle,
              message: "Workflow steps contain a cycle: #{cycle.join(' -> ')}.",
              details: { cycle: cycle }
            )
          end

          Result.ok(nodes: nodes, order: ids)
        end

        def downstream_closure(nodes, start_id)
          dependents = Hash.new { |h, k| h[k] = [] }
          nodes.each_value do |node|
            node[:requires].each { |req| dependents[req] << node[:id] }
          end

          visited = []
          queue = dependents[start_id.to_s].dup
          until queue.empty?
            current = queue.shift
            next if visited.include?(current)

            visited << current
            queue.concat(dependents[current])
          end

          visited
        end

        def collect_nodes(steps)
          ids = []
          nodes = {}

          steps.each_with_index do |step, index|
            id = step_id(step)
            if id.nil? || id.empty?
              return Result.err(
                code: :invalid_step_id,
                message: "Step at index #{index} is missing an id.",
                details: { index: index }
              )
            end

            if nodes.key?(id)
              return Result.err(
                code: :duplicate_step_id,
                message: "Step id '#{id}' appears more than once.",
                details: { id: id }
              )
            end

            ids << id
            nodes[id] = { id: id, requires: step_requires(step), index: index }
          end

          [ids, nodes]
        end

        def validate_requires(nodes)
          nodes.each_value do |node|
            node[:requires].each do |required|
              next if nodes.key?(required)

              return Result.err(
                code: :unknown_step_required,
                message: "Step '#{node[:id]}' requires unknown step '#{required}'.",
                details: { id: node[:id], unknown: required }
              )
            end
          end
          nil
        end

        def step_id(step)
          return nil unless step.is_a?(Hash)

          (step['id'] || step[:id])&.to_s
        end

        def step_requires(step)
          return [] unless step.is_a?(Hash)

          raw = step['requires'] || step[:requires] || []
          Array(raw).map(&:to_s)
        end

        def detect_cycle(nodes)
          color = {}
          stack = []

          catch(:cycle) do
            nodes.each_key do |id|
              visit_for_cycle(id, nodes, color, stack) if color[id].nil?
            end
            nil
          end
        end

        def visit_for_cycle(id, nodes, color, stack)
          color[id] = :gray
          stack << id

          nodes[id][:requires].each do |dep|
            case color[dep]
            when :gray
              throw(:cycle, stack[stack.index(dep)..] + [dep])
            when nil
              visit_for_cycle(dep, nodes, color, stack)
            end
          end

          color[id] = :black
          stack.pop
        end
      end
    end
  end
end
