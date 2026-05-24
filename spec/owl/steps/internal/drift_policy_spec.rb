# frozen_string_literal: true

require 'owl/steps/internal/drift_policy'

RSpec.describe Owl::Steps::Internal::DriftPolicy do
  describe '.for' do
    it 'returns :block for execution-typed steps with no declared policy' do
      step = { 'session_type' => 'execution' }
      expect(described_class.for(step)).to eq(:block)
    end

    it 'returns :warn for discussion-typed steps with no declared policy' do
      step = { 'session_type' => 'discussion' }
      expect(described_class.for(step)).to eq(:warn)
    end

    it 'returns :block when session_type is missing (defaults to execution)' do
      expect(described_class.for({})).to eq(:block)
    end

    it 'returns the declared policy when valid' do
      step = { 'session_type' => 'execution', 'drift_policy' => 'warn' }
      expect(described_class.for(step)).to eq(:warn)
    end

    it 'ignores an invalid declared policy and falls back to the default' do
      step = { 'session_type' => 'execution', 'drift_policy' => 'bogus' }
      expect(described_class.for(step)).to eq(:block)
    end

    it 'returns :ignore when override_ignore is true (--ignore-modification)' do
      step = { 'session_type' => 'execution', 'drift_policy' => 'block' }
      expect(described_class.for(step, override_ignore: true)).to eq(:ignore)
    end

    it 'handles a nil step_payload (falls back to :block)' do
      expect(described_class.for(nil)).to eq(:block)
    end
  end
end
