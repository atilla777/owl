# frozen_string_literal: true

module Owl
  module Validation
    module Internal
      module SectionsChecker
        HEADING_RE = /^\s{0,3}#+\s+(.+?)\s*$/

        module_function

        # Each entry is either a section name string (level defaults to `error`)
        # or a `{ name:, level: error|warning }` mapping. Warning-level sections
        # let a contract recommend structure without breaking existing artifacts.
        def check(body, required_sections)
          sections = Array(required_sections).filter_map { |entry| normalize(entry) }
          return [] if sections.empty?

          present = extract_headings(body.to_s)

          sections.reject { |s| present.include?(s[:name]) }.map do |s|
            {
              type: 'missing_section',
              section: s[:name],
              level: s[:level],
              description: "Required section '#{s[:name]}' not found."
            }
          end
        end

        def normalize(entry)
          if entry.is_a?(Hash)
            name = (entry['name'] || entry[:name]).to_s
            return nil if name.empty?

            level = (entry['level'] || entry[:level]).to_s
            { name: name, level: level == 'warning' ? 'warning' : 'error' }
          else
            name = entry.to_s
            name.empty? ? nil : { name: name, level: 'error' }
          end
        end

        def extract_headings(body)
          headings = []
          body.each_line do |line|
            match = line.match(HEADING_RE)
            headings << match[1] if match
          end
          headings
        end
      end
    end
  end
end
