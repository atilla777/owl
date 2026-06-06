# frozen_string_literal: true

require 'owl/validation/internal/sections_checker'

RSpec.describe Owl::Validation::Internal::SectionsChecker do
  let(:body) { "# Title\n## Goal\nx\n## Checklist\ny\n" }

  it 'returns no violations when all required sections are present' do
    expect(described_class.check(body, %w[Goal Checklist])).to eq([])
  end

  it 'flags a missing string section as error (default level)' do
    violations = described_class.check(body, %w[Goal Missing])
    expect(violations).to contain_exactly(
      a_hash_including(section: 'Missing', level: 'error', type: 'missing_section')
    )
  end

  it 'flags a missing {name, level: warning} section as warning' do
    violations = described_class.check(body, [{ 'name' => 'Scope', 'level' => 'warning' }])
    expect(violations).to contain_exactly(
      a_hash_including(section: 'Scope', level: 'warning')
    )
  end

  it 'treats {name} without level as error' do
    violations = described_class.check(body, [{ 'name' => 'Scope' }])
    expect(violations.first[:level]).to eq('error')
  end

  it 'tolerates symbol-keyed mappings' do
    violations = described_class.check(body, [{ name: 'Scope', level: 'warning' }])
    expect(violations.first).to include(section: 'Scope', level: 'warning')
  end

  it 'skips empty / nameless entries' do
    expect(described_class.check(body, ['', { 'name' => '' }, { 'level' => 'warning' }])).to eq([])
  end

  it 'returns [] for nil or empty required_sections' do
    expect(described_class.check(body, nil)).to eq([])
    expect(described_class.check(body, [])).to eq([])
  end
end
