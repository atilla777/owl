# frozen_string_literal: true

require 'owl/specs/internal/spec_document'
require 'owl/specs/internal/delta_merger'

RSpec.describe Owl::Specs::Internal::DeltaMerger do
  def model_for(*names)
    requirements = names.map do |name|
      { name: name, heading: "Requirement: #{name}", body: "### Requirement: #{name}\n\nThe system SHALL #{name}.\n\n" }
    end
    {
      frontmatter: "---\nstatus: draft\nsummary: s\n---\n",
      preamble: "\n## Requirements\n\n",
      requirements: requirements,
      tail: ''
    }
  end

  def block(name)
    body = "### Requirement: #{name}\n\nThe system SHALL new #{name}.\n"
    { name: name, heading: "Requirement: #{name}", body: body }
  end

  describe '.apply' do
    it 'appends ADDED requirements in delta order before the tail' do
      result = described_class.apply(model_for('A'), added: [block('B'), block('C')], modified: [], removed: [])
      expect(result).to be_ok
      expect(result.value[:requirements].map { |req| req[:name] }).to eq(%w[A B C])
    end

    it 'replaces a MODIFIED requirement in place, keeping its position' do
      result = described_class.apply(model_for('A', 'B', 'C'), added: [], modified: [block('B')], removed: [])
      expect(result).to be_ok
      names = result.value[:requirements].map { |req| req[:name] }
      expect(names).to eq(%w[A B C])
      modified = result.value[:requirements][1]
      expect(modified[:body]).to include('SHALL new B')
    end

    it 'deletes a REMOVED requirement' do
      result = described_class.apply(model_for('A', 'B', 'C'), added: [], modified: [], removed: ['B'])
      expect(result).to be_ok
      expect(result.value[:requirements].map { |req| req[:name] }).to eq(%w[A C])
    end

    it 'fails with delta_conflict when an ADDED name already exists' do
      result = described_class.apply(model_for('A'), added: [block('A')], modified: [], removed: [])
      expect(result).to be_err
      expect(result.code).to eq(:delta_conflict)
      expect(result.details[:name]).to eq('A')
    end

    it 'fails with delta_target_missing when a MODIFIED name is absent' do
      result = described_class.apply(model_for('A'), added: [], modified: [block('Z')], removed: [])
      expect(result).to be_err
      expect(result.code).to eq(:delta_target_missing)
      expect(result.details[:operation]).to eq('modified')
    end

    it 'fails with delta_target_missing when a REMOVED name is absent' do
      result = described_class.apply(model_for('A'), added: [], modified: [], removed: ['Z'])
      expect(result).to be_err
      expect(result.code).to eq(:delta_target_missing)
      expect(result.details[:operation]).to eq('removed')
    end

    it 'matches names case-sensitively' do
      result = described_class.apply(model_for('Alpha'), added: [], modified: [], removed: ['alpha'])
      expect(result).to be_err
      expect(result.code).to eq(:delta_target_missing)
    end

    it 'applies REMOVED then MODIFIED then ADDED so a removed name can be re-added' do
      result = described_class.apply(
        model_for('A', 'B'),
        added: [block('B')], modified: [], removed: ['B']
      )
      expect(result).to be_ok
      expect(result.value[:requirements].map { |req| req[:name] }).to eq(%w[A B])
      expect(result.value[:requirements].last[:body]).to include('SHALL new B')
    end

    it 'normalizes an inserted block without a trailing newline' do
      glued = { name: 'G', heading: 'Requirement: G', body: '### Requirement: G' }
      result = described_class.apply(model_for('A'), added: [glued], modified: [], removed: [])
      expect(result.value[:requirements].last[:body]).to eq("### Requirement: G\n")
    end

    it 'does not mutate the input model requirements' do
      model = model_for('A', 'B')
      original = model[:requirements].map { |req| req[:name] }
      described_class.apply(model, added: [], modified: [], removed: ['A'])
      expect(model[:requirements].map { |req| req[:name] }).to eq(original)
    end
  end
end
