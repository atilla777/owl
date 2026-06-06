# frozen_string_literal: true

require 'owl/specs/internal/spec_delta'

RSpec.describe Owl::Specs::Internal::SpecDelta do
  describe '.parse' do
    it 'parses ADDED, MODIFIED, and REMOVED sections into operations' do
      body = <<~MD
        # Delta

        ## ADDED Requirements

        ### Requirement: New cap

        The system SHALL add.

        #### Scenario: S
        - WHEN x
        - THEN y

        ## MODIFIED Requirements

        ### Requirement: Existing cap

        The system SHALL change.

        #### Scenario: S
        - WHEN x
        - THEN y

        ## REMOVED Requirements

        ### Requirement: Gone cap
      MD

      result = described_class.parse(body)
      expect(result).to be_ok
      expect(result.value[:added].map { |block| block[:name] }).to eq(['New cap'])
      expect(result.value[:modified].map { |block| block[:name] }).to eq(['Existing cap'])
      expect(result.value[:removed]).to eq(['Gone cap'])
    end

    it 'rejects an unknown "## X Requirements" section as invalid_delta' do
      body = "## RENAMED Requirements\n\n### Requirement: X\n\nThe system SHALL x.\n"
      result = described_class.parse(body)
      expect(result).to be_err
      expect(result.code).to eq(:invalid_delta)
    end

    it 'rejects a name appearing in more than one section as invalid_delta' do
      body = <<~MD
        ## ADDED Requirements

        ### Requirement: Dup

        The system SHALL dup.

        ## REMOVED Requirements

        ### Requirement: Dup
      MD
      result = described_class.parse(body)
      expect(result).to be_err
      expect(result.code).to eq(:invalid_delta)
      expect(result.message).to include('Dup')
    end

    it 'rejects an empty delta with no operations as invalid_delta' do
      result = described_class.parse("# Delta\n\nNo operations here.\n")
      expect(result).to be_err
      expect(result.code).to eq(:invalid_delta)
    end

    it 'rejects a delta whose only operation section carries no requirements' do
      result = described_class.parse("## ADDED Requirements\n\nnothing here\n")
      expect(result).to be_err
      expect(result.code).to eq(:invalid_delta)
    end

    it 'ignores non-"Requirements" level-2 headings' do
      body = <<~MD
        ## Notes

        Some context.

        ## ADDED Requirements

        ### Requirement: Only add

        The system SHALL add.
      MD
      result = described_class.parse(body)
      expect(result).to be_ok
      expect(result.value[:added].map { |block| block[:name] }).to eq(['Only add'])
    end
  end
end
