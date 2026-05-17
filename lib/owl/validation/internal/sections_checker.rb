# frozen_string_literal: true

module Owl
  module Validation
    module Internal
      module SectionsChecker
        HEADING_RE = /^\s{0,3}#+\s+(.+?)\s*$/

        module_function

        def check(body, required_sections)
          required = Array(required_sections).map(&:to_s)
          return [] if required.empty?

          present = extract_headings(body.to_s)

          required.reject { |name| present.include?(name) }.map do |name|
            {
              type: 'missing_section',
              section: name,
              level: 'error',
              description: "Required section '#{name}' not found."
            }
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
