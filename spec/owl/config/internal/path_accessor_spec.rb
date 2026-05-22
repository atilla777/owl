# frozen_string_literal: true

require 'owl/config/internal/path_accessor'

RSpec.describe Owl::Config::Internal::PathAccessor do
  describe '.read' do
    it 'reads a leaf value under any root segment, not only settings' do
      raw = { 'workflow' => { 'feature' => { 'phases' => %w[plan implement] } } }
      expect(described_class.read(raw, 'workflow.feature.phases')).to eq(%w[plan implement])
    end

    it 'reads a leaf value under settings.* (legacy behaviour preserved)' do
      raw = { 'settings' => { 'language' => { 'communication' => 'en' } } }
      expect(described_class.read(raw, 'settings.language.communication')).to eq('en')
    end

    it 'raises MissingKeyError when a segment is absent regardless of root' do
      expect { described_class.read({ 'workflow' => {} }, 'workflow.feature.phases') }
        .to raise_error(described_class::MissingKeyError)
      expect { described_class.read({ 'settings' => {} }, 'settings.absent') }
        .to raise_error(described_class::MissingKeyError)
    end

    it 'raises InvalidPathError for an empty or nil path' do
      expect { described_class.read({}, nil) }.to raise_error(described_class::InvalidPathError)
      expect { described_class.read({}, '') }.to raise_error(described_class::InvalidPathError)
    end

    it 'raises InvalidPathError for a path with an empty segment' do
      expect { described_class.read({}, 'workflow..phases') }
        .to raise_error(described_class::InvalidPathError)
    end
  end

  describe '.write' do
    it 'writes a leaf value under any root segment, not only settings' do
      raw = {}
      described_class.write(raw, 'workflow.feature.phases', %w[plan implement])
      expect(raw).to eq('workflow' => { 'feature' => { 'phases' => %w[plan implement] } })
    end

    it 'writes a leaf value under settings.* (legacy behaviour preserved)' do
      raw = {}
      described_class.write(raw, 'settings.language.communication', 'ru')
      expect(raw).to eq('settings' => { 'language' => { 'communication' => 'ru' } })
    end

    it 'raises InvalidPathError when an intermediate segment is not a Hash' do
      raw = { 'workflow' => { 'feature' => 'not-a-hash' } }
      expect { described_class.write(raw, 'workflow.feature.phases', 'x') }
        .to raise_error(described_class::InvalidPathError)
    end

    it 'raises InvalidPathError for empty / empty-segment paths' do
      expect { described_class.write({}, nil, 'x') }.to raise_error(described_class::InvalidPathError)
      expect { described_class.write({}, '', 'x') }.to raise_error(described_class::InvalidPathError)
      expect { described_class.write({}, 'workflow..phases', 'x') }
        .to raise_error(described_class::InvalidPathError)
    end
  end

  describe 'removed whitelist surface' do
    it 'does not define SUPPORTED_ROOT constant' do
      expect(described_class.const_defined?(:SUPPORTED_ROOT)).to be(false)
    end

    it 'does not define UnsupportedPathError constant' do
      expect(described_class.const_defined?(:UnsupportedPathError)).to be(false)
    end

    it 'does not define supported? / ensure_supported! helpers' do
      expect(described_class).not_to respond_to(:supported?)
      expect(described_class).not_to respond_to(:ensure_supported!)
    end
  end
end
