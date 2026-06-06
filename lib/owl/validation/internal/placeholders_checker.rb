# frozen_string_literal: true

require_relative 'section_scanner'

module Owl
  module Validation
    module Internal
      # Opt-in checker for `forbid_placeholders`. When the spec is `true` the
      # default marker list is used; an array of strings overrides it. Markers
      # are matched as case-sensitive substrings on lines that are not inside a
      # fenced code block.
      module PlaceholdersChecker
        DEFAULT_MARKERS = %w[TODO TBD FIXME XXX <...>].freeze

        module_function

        def check(body, spec)
          markers = markers_for(spec)
          return [] if markers.empty?

          mask = SectionScanner.code_line_mask(body)
          headings = SectionScanner.headings(body)
          violations = []
          body.to_s.lines.each_with_index do |line, index|
            next if mask[index]

            markers.each do |marker|
              next unless line.include?(marker)

              violations << violation(headings, index, marker)
            end
          end
          violations
        end

        def markers_for(spec)
          return [] if spec.nil? || spec == false
          return DEFAULT_MARKERS if spec == true

          Array(spec).map(&:to_s).reject(&:empty?)
        end

        def violation(headings, line_index, marker)
          section = section_for(headings, line_index)
          {
            type: 'placeholder_text',
            section: section,
            marker: marker,
            level: 'error',
            description: "Placeholder '#{marker}' found in section '#{section}'."
          }
        end

        def section_for(headings, line_index)
          preceding = headings.reverse.find { |heading| heading[:line] < line_index }
          preceding ? preceding[:heading] : '(document)'
        end
      end
    end
  end
end
