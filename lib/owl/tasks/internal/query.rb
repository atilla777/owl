# frozen_string_literal: true

require_relative '../../result'
require_relative 'index_reader'
require_relative 'paths'

module Owl
  module Tasks
    module Internal
      # Filters the materialized `tasks/index.yaml` roster by combinable AND
      # predicates (status / label / priority / parent / workflow). Works off
      # the index alone so a query never reads every task.yaml.
      module Query
        module_function

        def call(root:, filters: {})
          paths_result = Paths.resolve(root: root)
          return paths_result if paths_result.err?

          index = IndexReader.read(index_path: paths_result.value[:index])
          return index if index.err?

          tasks = Array(index.value[:tasks]).select { |entry| match?(entry, filters) }
          Result.ok(tasks: tasks)
        end

        def match?(entry, filters)
          return false unless entry.is_a?(Hash)

          predicates(filters).all? { |predicate| predicate.call(entry) }
        end

        def predicates(filters)
          checks = []
          checks << ->(e) { (e['status'] || 'open') == filters[:status] } unless filters[:status].nil?
          checks << ->(e) { Array(e['labels']).include?(filters[:label]) } unless filters[:label].nil?
          checks << ->(e) { e['priority'] == filters[:priority] } unless filters[:priority].nil?
          checks << ->(e) { e['parent_id'] == filters[:parent] } unless filters[:parent].nil?
          checks << ->(e) { e['workflow'] == filters[:workflow] } unless filters[:workflow].nil?
          checks
        end
      end
    end
  end
end
