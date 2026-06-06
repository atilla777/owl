# frozen_string_literal: true

require_relative 'section_scanner'

module Owl
  module Validation
    module Internal
      # Opt-in checker for `require_when_then: true`. Every `#### Scenario` block
      # (spanning to the next heading of level <= 4 or EOF) must contain both a
      # WHEN line and a THEN line. Matching tolerates leading blockquote/list
      # bullets and bold markers.
      module WhenThenChecker
        SCENARIO_RE = /\AScenario\b/
        CLAUSE_RES = {
          'WHEN' => /\A[\s>*-]*\**\s*WHEN\b/,
          'THEN' => /\A[\s>*-]*\**\s*THEN\b/
        }.freeze

        module_function

        def check(body, enabled)
          return [] unless enabled

          lines = body.to_s.lines
          headings = SectionScanner.headings(body)
          violations = []
          headings.each_with_index do |heading, idx|
            next unless scenario?(heading)

            block = block_lines(lines, headings, idx)
            CLAUSE_RES.each do |keyword, regex|
              next if block.any? { |line| line.match?(regex) }

              violations << violation(heading[:heading], keyword)
            end
          end
          violations
        end

        def scenario?(heading)
          heading[:level] == 4 && heading[:heading].match?(SCENARIO_RE)
        end

        def block_lines(lines, headings, idx)
          start = headings[idx][:line] + 1
          following = headings[(idx + 1)..].find { |heading| heading[:level] <= 4 }
          finish = following ? following[:line] : lines.length
          lines[start...finish]
        end

        def violation(scenario, keyword)
          {
            type: 'scenario_missing_clause',
            scenario: scenario,
            missing: keyword,
            level: 'error',
            description: "Scenario '#{scenario}' is missing a #{keyword} clause."
          }
        end
      end
    end
  end
end
