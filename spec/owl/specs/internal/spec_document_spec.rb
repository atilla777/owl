# frozen_string_literal: true

require 'owl/specs/internal/spec_document'

RSpec.describe Owl::Specs::Internal::SpecDocument do
  let(:body) do
    <<~MD
      ---
      status: active
      summary: Billing rules.
      ---

      # Spec

      ## Purpose

      Billing behaviour.

      ## Requirements

      ### Requirement: Invoices are issued

      The system SHALL issue an invoice.

      #### Scenario: Issue
      - WHEN a sale completes
      - THEN an invoice is issued

      ### Requirement: Refunds

      The system SHALL allow refunds.

      #### Scenario: Refund
      - WHEN a refund is requested
      - THEN money is returned

      ## Notes

      trailing section here
    MD
  end

  describe '.parse' do
    it 'splits a spec into frontmatter, preamble, requirements, and tail' do
      model = described_class.parse(body)

      expect(model[:frontmatter]).to eq("---\nstatus: active\nsummary: Billing rules.\n---\n")
      expect(model[:requirements].map { |req| req[:name] }).to eq(['Invoices are issued', 'Refunds'])
      expect(model[:preamble]).to include('## Purpose')
      expect(model[:tail]).to start_with('## Notes')
    end

    it 'treats a nested #### Scenario as part of its requirement, not a boundary' do
      model = described_class.parse(body)
      first = model[:requirements].first
      expect(first[:body]).to include('#### Scenario: Issue')
      expect(first[:body]).not_to include('Refunds')
    end

    it 'returns the whole body as preamble when there are no requirements' do
      text = "# Spec\n\n## Purpose\n\nNothing formal here.\n"
      model = described_class.parse(text)
      expect(model[:requirements]).to eq([])
      expect(model[:preamble]).to eq(text)
      expect(model[:tail]).to eq('')
    end

    it 'handles a body with no frontmatter' do
      text = "## Requirements\n\n### Requirement: X\n\nThe system SHALL X.\n"
      model = described_class.parse(text)
      expect(model[:frontmatter]).to eq('')
      expect(model[:requirements].map { |req| req[:name] }).to eq(['X'])
    end

    it 'does not treat fenced code that looks like a heading as a requirement' do
      text = <<~MD
        ## Requirements

        ### Requirement: Real

        The system SHALL be real.

        ```
        ### Requirement: Fake inside a fence
        ```

        #### Scenario: S
        - WHEN x
        - THEN y
      MD
      model = described_class.parse(text)
      expect(model[:requirements].map { |req| req[:name] }).to eq(['Real'])
      expect(model[:requirements].first[:body]).to include('Fake inside a fence')
    end

    it 'trims trailing whitespace from the requirement name' do
      text = "### Requirement:   Spaced name   \n\nThe system SHALL space.\n"
      model = described_class.parse(text)
      expect(model[:requirements].first[:name]).to eq('Spaced name')
    end
  end

  describe '.serialize' do
    it 'is the exact inverse of parse for an untouched spec (round-trip identity)' do
      expect(described_class.serialize(described_class.parse(body))).to eq(body)
    end

    it 'round-trips a body without frontmatter or tail' do
      text = "## Requirements\n\n### Requirement: A\n\nThe system SHALL a.\n\n" \
             "### Requirement: B\n\nThe system SHALL b.\n"
      expect(described_class.serialize(described_class.parse(text))).to eq(text)
    end
  end

  describe '.requirement_blocks' do
    it 'extracts each requirement block from an arbitrary chunk' do
      chunk = "### Requirement: One\n\nbody one\n\n### Requirement: Two\n\nbody two\n"
      blocks = described_class.requirement_blocks(chunk)
      expect(blocks.map { |block| block[:name] }).to eq(%w[One Two])
      expect(blocks.first[:body]).to eq("### Requirement: One\n\nbody one\n\n")
    end

    it 'returns an empty list when there are no requirement headings' do
      expect(described_class.requirement_blocks("just prose\n")).to eq([])
    end
  end
end
