# frozen_string_literal: true

require_relative 'section_scanner'

module Owl
  module Validation
    module Internal
      # Opt-in checker for `require_scenarios: true`. Every `### Requirement`
      # heading must be followed by at least one `#### Scenario` heading before
      # the next level-3 (or higher) heading or EOF.
      module ScenariosChecker
        REQUIREMENT_RE = /\ARequirement\b/
        SCENARIO_RE = /\AScenario\b/

        module_function

        def check(body, enabled)
          return [] unless enabled

          headings = SectionScanner.headings(body)
          headings.each_with_index.filter_map do |heading, idx|
            next unless requirement?(heading)
            next if scenario_follows?(headings, idx)

            {
              type: 'requirement_without_scenario',
              requirement: heading[:heading],
              level: 'error',
              description: "Requirement '#{heading[:heading]}' has no scenario."
            }
          end
        end

        def requirement?(heading)
          heading[:level] == 3 && heading[:heading].match?(REQUIREMENT_RE)
        end

        def scenario_follows?(headings, idx)
          headings[(idx + 1)..].each do |heading|
            break if heading[:level] <= 3
            return true if heading[:level] == 4 && heading[:heading].match?(SCENARIO_RE)
          end
          false
        end
      end
    end
  end
end
