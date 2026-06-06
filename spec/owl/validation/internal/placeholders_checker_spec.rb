# frozen_string_literal: true

require 'owl/validation/internal/placeholders_checker'

RSpec.describe Owl::Validation::Internal::PlaceholdersChecker do
  describe '.check' do
    it 'returns [] when spec is falsy or an empty array' do
      expect(described_class.check('TODO here', nil)).to eq([])
      expect(described_class.check('TODO here', false)).to eq([])
      expect(described_class.check('TODO here', [])).to eq([])
      expect(described_class.check('TODO here', ['   '])).to eq([])
    end

    it 'flags default markers with the nearest preceding heading' do
      body = "## Section\n\nthis is TODO still\n"
      violations = described_class.check(body, true)
      expect(violations.first).to include(
        type: 'placeholder_text', section: 'Section', marker: 'TODO', level: 'error'
      )
    end

    it 'uses (document) when there is no preceding heading' do
      violations = described_class.check("TBD at top\n", true)
      expect(violations.first[:section]).to eq('(document)')
      expect(violations.first[:marker]).to eq('TBD')
    end

    it 'exempts markers inside fenced code blocks' do
      body = "## S\n\n```\nTODO sample in code\n```\n\nclean prose\n"
      expect(described_class.check(body, true)).to eq([])
    end

    it 'honours a custom marker list and matches case-sensitively' do
      body = "## S\n\nPENDING work and pending work\n"
      violations = described_class.check(body, ['PENDING'])
      expect(violations.length).to eq(1)
      expect(violations.first[:marker]).to eq('PENDING')
    end

    it 'emits one violation per marker matched on a line' do
      body = "## S\n\nTODO and FIXME together\n"
      markers = described_class.check(body, true).map { |v| v[:marker] }
      expect(markers).to contain_exactly('TODO', 'FIXME')
    end

    it 'matches the literal angle-bracket placeholder' do
      violations = described_class.check("## S\n\nreplace <...> here\n", true)
      expect(violations.map { |v| v[:marker] }).to eq(['<...>'])
    end
  end
end
