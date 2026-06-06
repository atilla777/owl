# frozen_string_literal: true

require 'owl/validation/internal/empty_sections_checker'

RSpec.describe Owl::Validation::Internal::EmptySectionsChecker do
  describe '.check' do
    it 'returns [] when disabled regardless of content' do
      expect(described_class.check("## Empty\n\n## Also\n", false)).to eq([])
      expect(described_class.check('## Empty', nil)).to eq([])
    end

    it 'flags a heading whose body is only whitespace' do
      violations = described_class.check("## Filled\n\ntext\n\n## Empty\n\n   \n", true)
      expect(violations.length).to eq(1)
      expect(violations.first).to include(type: 'empty_section', section: 'Empty', level: 'error')
    end

    it 'treats a section containing only an HTML comment as empty' do
      violations = described_class.check("## Hollow\n\n<!-- TODO fill -->\n", true)
      expect(violations.map { |v| v[:section] }).to eq(%w[Hollow])
    end

    it 'passes when every section has real content' do
      expect(described_class.check("## A\n\nalpha\n\n## B\n\nbeta\n", true)).to eq([])
    end

    it 'flags a parent heading that only holds subheadings (tight span)' do
      violations = described_class.check("## Parent\n\n### Child\n\nbody\n", true)
      expect(violations.map { |v| v[:section] }).to eq(%w[Parent])
    end
  end
end
