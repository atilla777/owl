# frozen_string_literal: true

module Owl
  module Internal
    # Generic directed-graph cycle detector over an adjacency map
    # (`id => [neighbor ids]`). Extracted from the workflow graph builder so the
    # same DFS three-colour walk backs both workflow-step `requires` validation
    # and cross-task `blocked_by` dependency validation — one implementation, no
    # duplication.
    #
    # Returns the cycle as an id path whose first and last element are equal
    # (`a -> b -> c -> a`) when one exists, or `nil` for an acyclic graph.
    # Neighbors that are not themselves keys of the adjacency map are tolerated
    # (treated as leaves), so a dangling reference never raises.
    module CycleDetector
      module_function

      def detect(adjacency)
        color = {}
        stack = []

        catch(:cycle) do
          adjacency.each_key do |id|
            visit(id, adjacency, color, stack) if color[id].nil?
          end
          nil
        end
      end

      def visit(id, adjacency, color, stack)
        color[id] = :gray
        stack << id

        Array(adjacency[id]).each do |neighbor|
          case color[neighbor]
          when :gray
            throw(:cycle, stack[stack.index(neighbor)..] + [neighbor])
          when nil
            visit(neighbor, adjacency, color, stack)
          end
        end

        color[id] = :black
        stack.pop
      end
    end
  end
end
