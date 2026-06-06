# frozen_string_literal: true

require 'owl/validation/internal/when_then_checker'

RSpec.describe Owl::Validation::Internal::WhenThenChecker do
  describe '.check' do
    it 'returns [] when disabled' do
      expect(described_class.check("#### Scenario: x\n", false)).to eq([])
    end

    it 'flags a scenario missing THEN' do
      body = <<~MD
        #### Scenario: half
        - WHEN something happens
      MD
      violations = described_class.check(body, true)
      expect(violations).to eq(
        [{ type: 'scenario_missing_clause', scenario: 'Scenario: half', missing: 'THEN', level: 'error',
           description: "Scenario 'Scenario: half' is missing a THEN clause." }]
      )
    end

    it 'reports both clauses when neither is present' do
      missing = described_class.check("#### Scenario: empty\n\njust prose\n", true).map { |v| v[:missing] }
      expect(missing).to eq(%w[WHEN THEN])
    end

    it 'passes with plain WHEN/THEN lines' do
      body = "#### Scenario: ok\nWHEN a\nTHEN b\n"
      expect(described_class.check(body, true)).to eq([])
    end

    it 'tolerates leading bullets and bold markers' do
      body = <<~MD
        #### Scenario: styled
        - **WHEN** the user acts
        * THEN the system responds
      MD
      expect(described_class.check(body, true)).to eq([])
    end

    it 'spans a scenario across deeper sub-headings until the next level-4 heading' do
      body = <<~MD
        #### Scenario: nested
        WHEN a
        ##### detail
        THEN b
        #### Scenario: next
        WHEN c
        THEN d
      MD
      expect(described_class.check(body, true)).to eq([])
    end

    it 'stops a scenario block at the next level-3 heading' do
      body = <<~MD
        #### Scenario: cut
        WHEN a
        ### Requirement: other
        THEN b
      MD
      expect(described_class.check(body, true).map { |v| v[:missing] }).to eq(%w[THEN])
    end
  end
end
