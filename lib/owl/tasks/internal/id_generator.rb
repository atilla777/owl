# frozen_string_literal: true

require 'pathname'
require 'yaml'

module Owl
  module Tasks
    module Internal
      module IdGenerator
        PREFIX = 'TASK-'
        ID_PATTERN = /\ATASK-(\d{4,})\z/
        DIGITS = 4

        module_function

        def next_id(tasks_root:, index_path:)
          highest = [
            highest_from_index(index_path),
            highest_from_directories(tasks_root)
          ].max

          format("#{PREFIX}%0#{DIGITS}d", highest + 1)
        end

        def parse(id)
          match = ID_PATTERN.match(id.to_s)
          match ? Integer(match[1], 10) : nil
        end

        def highest_from_index(index_path)
          path = Pathname.new(index_path.to_s)
          return 0 unless path.exist?

          raw = YAML.safe_load(path.read, aliases: false)
          return 0 unless raw.is_a?(Hash)

          entries = raw['tasks']
          return 0 unless entries.is_a?(Array)

          entries.filter_map { |e| parse(e.is_a?(Hash) ? e['id'] : nil) }.max || 0
        rescue Psych::SyntaxError
          0
        end

        def highest_from_directories(tasks_root)
          dir = Pathname.new(tasks_root.to_s)
          return 0 unless dir.directory?

          dir.children.filter_map do |entry|
            next unless entry.directory?

            parse(entry.basename.to_s)
          end.max || 0
        end
      end
    end
  end
end
