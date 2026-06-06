# frozen_string_literal: true

require 'owl/validation/internal/section_scanner'

RSpec.describe Owl::Validation::Internal::SectionScanner do
  describe '.headings' do
    it 'returns headings with their level and line index' do
      body = "# Title\n\ntext\n\n## Sub\n\nmore\n### Deep\n"
      expect(described_class.headings(body)).to eq(
        [
          { heading: 'Title', level: 1, line: 0 },
          { heading: 'Sub', level: 2, line: 4 },
          { heading: 'Deep', level: 3, line: 7 }
        ]
      )
    end

    it 'ignores hash characters inside fenced code blocks' do
      body = "# Real\n\n```\n# not a heading\n```\n\n## Also real\n"
      expect(described_class.headings(body).map { |h| h[:heading] }).to eq(%w[Real] + ['Also real'])
    end

    it 'treats tilde fences the same as backtick fences' do
      body = "# Real\n~~~\n## fake\n~~~\n## After\n"
      expect(described_class.headings(body).map { |h| h[:heading] }).to eq(%w[Real After])
    end
  end

  describe '.code_line_mask' do
    it 'marks fence and inner lines as inside the block' do
      body = "a\n```\ncode\n```\nb\n"
      expect(described_class.code_line_mask(body)).to eq([false, true, true, true, false])
    end

    it 'leaves an unterminated fence open until EOF' do
      body = "a\n```\ncode\n"
      expect(described_class.code_line_mask(body)).to eq([false, true, true])
    end
  end

  describe '.sections' do
    it 'splits the body into per-heading segments up to the next heading of any level' do
      body = "## A\n\nalpha\n\n### B\n\nbeta\n## C\n\ngamma\n"
      sections = described_class.sections(body)
      expect(sections.map { |s| s[:heading] }).to eq(%w[A B C])
      expect(sections[0][:body]).to eq("\nalpha\n\n")
      expect(sections[1][:body]).to eq("\nbeta\n")
      expect(sections[2][:body]).to eq("\ngamma\n")
    end

    it 'returns an empty list when there are no headings' do
      expect(described_class.sections("just prose\nno headings\n")).to eq([])
    end
  end
end
