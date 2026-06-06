# frozen_string_literal: true

require 'owl/validation/internal/scenarios_checker'

RSpec.describe Owl::Validation::Internal::ScenariosChecker do
  describe '.check' do
    it 'returns [] when disabled' do
      expect(described_class.check("### Requirement: x\n", false)).to eq([])
    end

    it 'flags a requirement with no scenario before the next requirement' do
      body = <<~MD
        ### Requirement: Lonely

        Some text.

        ### Requirement: Paired

        #### Scenario: ok
        - WHEN a
        - THEN b
      MD
      violations = described_class.check(body, true)
      expect(violations.length).to eq(1)
      expect(violations.first).to include(
        type: 'requirement_without_scenario', requirement: 'Requirement: Lonely', level: 'error'
      )
    end

    it 'passes when every requirement has at least one scenario' do
      body = <<~MD
        ### Requirement: One
        #### Scenario: a

        ### Requirement: Two
        #### Scenario: b
      MD
      expect(described_class.check(body, true)).to eq([])
    end

    it 'counts deeper non-scenario headings as zero scenarios' do
      body = <<~MD
        ### Requirement: Deep
        ##### Note: not a scenario
        text
      MD
      expect(described_class.check(body, true).map { |v| v[:requirement] }).to eq(['Requirement: Deep'])
    end

    it 'ignores level-4 scenarios that belong to a later requirement' do
      body = <<~MD
        ### Requirement: First

        ### Requirement: Second
        #### Scenario: only here
      MD
      expect(described_class.check(body, true).map { |v| v[:requirement] }).to eq(['Requirement: First'])
    end
  end
end
