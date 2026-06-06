# frozen_string_literal: true

require_relative 'section_scanner'

module Owl
  module Validation
    module Internal
      # Opt-in checker for `forbid_empty_sections: true`. Flags any heading whose
      # body (up to the next heading of any level or EOF) is empty once
      # whitespace, blank lines and HTML comments are stripped.
      module EmptySectionsChecker
        COMMENT_RE = /<!--.*?-->/m

        module_function

        def check(body, enabled)
          return [] unless enabled

          SectionScanner.sections(body).filter_map do |segment|
            next unless empty?(segment[:body])

            {
              type: 'empty_section',
              section: segment[:heading],
              level: 'error',
              description: "Section '#{segment[:heading]}' is empty."
            }
          end
        end

        def empty?(text)
          text.gsub(COMMENT_RE, '').gsub(/\s+/, '').empty?
        end
      end
    end
  end
end
