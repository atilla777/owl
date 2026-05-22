# frozen_string_literal: true

require 'owl/steps/internal/step_projection'

RSpec.describe Owl::Steps::Internal::StepProjection do
  describe '.title' do
    it 'returns the title string when present' do
      expect(described_class.title('title' => 'Brief')).to eq('Brief')
    end

    it 'returns empty string when missing' do
      expect(described_class.title({})).to eq('')
    end

    it 'returns empty string for nil step' do
      expect(described_class.title(nil)).to eq('')
    end

    it 'reads symbol keys' do
      expect(described_class.title(title: 'Foo')).to eq('Foo')
    end
  end

  describe '.optional' do
    it 'returns false when key absent' do
      expect(described_class.optional({})).to be false
    end

    it 'returns false for nil step' do
      expect(described_class.optional(nil)).to be false
    end

    it 'returns true for boolean true' do
      expect(described_class.optional('optional' => true)).to be true
    end

    it 'returns false for boolean false' do
      expect(described_class.optional('optional' => false)).to be false
    end

    it 'normalizes string "true" to true' do
      expect(described_class.optional('optional' => 'true')).to be true
    end

    it 'normalizes string "false" to false' do
      expect(described_class.optional('optional' => 'false')).to be false
    end

    it 'normalizes string "yes" to true' do
      expect(described_class.optional('optional' => 'yes')).to be true
    end

    it 'normalizes string "no" to false' do
      expect(described_class.optional('optional' => 'no')).to be false
    end

    it 'normalizes string "1" to true' do
      expect(described_class.optional('optional' => '1')).to be true
    end

    it 'normalizes string "0" to false' do
      expect(described_class.optional('optional' => '0')).to be false
    end

    it 'is case insensitive for string forms' do
      expect(described_class.optional('optional' => 'TRUE')).to be true
      expect(described_class.optional('optional' => 'False')).to be false
    end

    it 'raises ArgumentError for invalid values' do
      expect { described_class.optional('optional' => 'maybe') }
        .to raise_error(ArgumentError, /cannot normalize/)
    end
  end

  describe '.session_type' do
    it 'returns "execution" as the default' do
      expect(described_class.session_type({})).to eq('execution')
    end

    it 'returns "execution" for nil step' do
      expect(described_class.session_type(nil)).to eq('execution')
    end

    it 'returns the declared discussion value' do
      expect(described_class.session_type('session_type' => 'discussion')).to eq('discussion')
    end

    it 'returns the declared execution value' do
      expect(described_class.session_type('session_type' => 'execution')).to eq('execution')
    end

    it 'falls back to default for unknown values with a warning' do
      result = nil
      expect { result = described_class.session_type('session_type' => 'mystery') }
        .to output(/StepProjection.session_type/).to_stderr
      expect(result).to eq('execution')
    end
  end

  describe '.variants_keys' do
    it 'returns empty array when no variants' do
      expect(described_class.variants_keys({})).to eq([])
    end

    it 'returns empty array for nil step' do
      expect(described_class.variants_keys(nil)).to eq([])
    end

    it 'returns sorted variant keys' do
      step = { 'variants' => { 'c' => {}, 'a' => {}, 'b' => {} } }
      expect(described_class.variants_keys(step)).to eq(%w[a b c])
    end

    it 'returns [] when variants is not a Hash' do
      expect(described_class.variants_keys('variants' => 'oops')).to eq([])
    end
  end

  describe '.model_tier' do
    it 'returns "standard" as the default' do
      expect(described_class.model_tier({})).to eq('standard')
    end

    it 'returns "standard" for nil step' do
      expect(described_class.model_tier(nil)).to eq('standard')
    end

    it 'reads from the `tier` YAML key' do
      expect(described_class.model_tier('tier' => 'advanced')).to eq('advanced')
    end

    it 'returns standard tier explicitly' do
      expect(described_class.model_tier('tier' => 'standard')).to eq('standard')
    end

    it 'falls back to default for unknown tier with a warning' do
      result = nil
      expect { result = described_class.model_tier('tier' => 'platinum') }
        .to output(/StepProjection.model_tier/).to_stderr
      expect(result).to eq('standard')
    end
  end

  describe '.project' do
    it 'returns the full contract hash with symbol keys' do
      step = {
        'title' => 'Brief',
        'optional' => true,
        'session_type' => 'discussion',
        'variants' => { 'b' => {}, 'a' => {} },
        'tier' => 'advanced'
      }
      expect(described_class.project(step)).to eq(
        title: 'Brief',
        optional: true,
        session_type: 'discussion',
        variants_keys: %w[a b],
        model_tier: 'advanced'
      )
    end

    it 'fills defaults for an empty step' do
      expect(described_class.project({})).to eq(
        title: '',
        optional: false,
        session_type: 'execution',
        variants_keys: [],
        model_tier: 'standard'
      )
    end

    it 'fills defaults for a nil step' do
      expect(described_class.project(nil)).to eq(
        title: '',
        optional: false,
        session_type: 'execution',
        variants_keys: [],
        model_tier: 'standard'
      )
    end
  end
end
