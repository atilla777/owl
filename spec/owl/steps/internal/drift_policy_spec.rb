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

  describe '.for with check: keyword (KOS-156)' do
    it 'returns :warn for step_context_frontmatter on a discussion step with no explicit policy' do
      step = { 'session_type' => 'discussion' }
      expect(described_class.for(step, check: :step_context_frontmatter)).to eq(:warn)
    end

    it 'returns :warn for step_context_frontmatter on an execution step ' \
       '(check default overrides session_type default)' do
      step = { 'session_type' => 'execution' }
      expect(described_class.for(step, check: :step_context_frontmatter)).to eq(:warn)
    end

    it 'respects an explicit per-step drift_policy: block over the check default' do
      step = { 'session_type' => 'discussion', 'drift_policy' => 'block' }
      expect(described_class.for(step, check: :step_context_frontmatter)).to eq(:block)
    end

    it 'respects an explicit per-step drift_policy: ignore over the check default' do
      step = { 'session_type' => 'execution', 'drift_policy' => 'ignore' }
      expect(described_class.for(step, check: :step_context_frontmatter)).to eq(:ignore)
    end

    it 'still returns :ignore when override_ignore is true regardless of check:' do
      step = { 'session_type' => 'execution', 'drift_policy' => 'block' }
      expect(described_class.for(step, override_ignore: true, check: :step_context_frontmatter)).to eq(:ignore)
    end

    it 'falls back to session_type default for an unknown check key' do
      step = { 'session_type' => 'execution' }
      expect(described_class.for(step, check: :unknown_check)).to eq(:block)
    end

    it 'preserves backwards-compat when check: is nil (callers like step_start.rb)' do
      step = { 'session_type' => 'execution' }
      expect(described_class.for(step, check: nil)).to eq(:block)
      step = { 'session_type' => 'discussion' }
      expect(described_class.for(step, check: nil)).to eq(:warn)
    end
  end

  describe '::BUILT_IN_CHECK_DEFAULTS' do
    it 'declares :step_context_frontmatter => :warn' do
      expect(described_class::BUILT_IN_CHECK_DEFAULTS).to eq(step_context_frontmatter: :warn)
    end

    it 'is frozen' do
      expect(described_class::BUILT_IN_CHECK_DEFAULTS).to be_frozen
    end
  end
end
