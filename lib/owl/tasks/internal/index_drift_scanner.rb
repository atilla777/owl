# frozen_string_literal: true

require_relative '../../result'
require_relative 'index_reader'
require_relative 'index_rebuilder'
require_relative 'paths'

module Owl
  module Tasks
    module Internal
      # Read-only detector for `tasks/index.yaml` ↔ `tasks/<ID>/task.yaml`
      # drift: the index is a projection of the per-task files, and the two can
      # silently diverge (a hand-edit, an interrupted mutation, an external
      # tool). This scanner compares the on-disk index against the canonical
      # projection `IndexRebuilder.project` would write and classifies every
      # discrepancy. It never writes — `owl doctor --fix` reconciles by calling
      # the existing `Tasks::Api.rebuild_index`.
      module IndexDriftScanner
        # Index entry fields compared for the `field_mismatch` class. `id` is the
        # join key, so it is excluded from the value comparison.
        COMPARED_FIELDS = %w[title workflow kind parent_id priority created_at
                             status labels blocked_by archived_at].freeze

        module_function

        def scan(root:)
          paths_result = Paths.resolve(root: root)
          return paths_result if paths_result.err?

          expected_result = expected_entries(tasks_root: paths_result.value[:tasks])
          actual_result = actual_entries(index_path: paths_result.value[:index])
          return actual_result if actual_result.err?

          Result.ok(index_drift: diff(expected: expected_result, actual: actual_result.value))
        end

        def expected_entries(tasks_root:)
          IndexRebuilder.project(tasks_root: tasks_root)[:tasks]
        end

        def actual_entries(index_path:)
          read = IndexReader.read(index_path: index_path)
          return read if read.err?

          Result.ok(Array(read.value[:tasks]).grep(Hash))
        end

        def diff(expected:, actual:)
          expected_by_id = index_by_id(expected)
          actual_by_id = index_by_id(actual)
          ids = (expected_by_id.keys + actual_by_id.keys).uniq.sort

          ids.filter_map do |id|
            classify(id: id, expected: expected_by_id[id], actual: actual_by_id[id])
          end
        end

        def classify(id:, expected:, actual:)
          if actual.nil?
            { task_id: id, class: 'missing_from_index' }
          elsif expected.nil?
            { task_id: id, class: 'stale_in_index' }
          else
            mismatched = COMPARED_FIELDS.reject { |field| expected[field] == actual[field] }
            return nil if mismatched.empty?

            { task_id: id, class: 'field_mismatch', fields: mismatched }
          end
        end

        def index_by_id(entries)
          Array(entries).each_with_object({}) do |entry, acc|
            next unless entry.is_a?(Hash)

            id = entry['id'].to_s
            acc[id] = entry unless id.empty?
          end
        end
      end
    end
  end
end
