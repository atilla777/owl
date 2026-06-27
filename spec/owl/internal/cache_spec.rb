# frozen_string_literal: true

require 'owl/internal/cache'

RSpec.describe Owl::Internal::Cache do
  describe '.fetch' do
    it 'invokes the block once for the same key and version token' do
      calls = 0
      block = lambda {
        calls += 1
        :value
      }

      described_class.fetch('k', version_token: 't', &block)
      described_class.fetch('k', version_token: 't', &block)

      expect(calls).to eq(1)
    end

    it 're-invokes the block when the version token changes' do
      calls = 0
      block = lambda {
        calls += 1
        :value
      }

      described_class.fetch('k', version_token: 't1', &block)
      described_class.fetch('k', version_token: 't2', &block)

      expect(calls).to eq(2)
    end

    it 'returns the cached value, not the new block result, when token matches' do
      described_class.fetch('k', version_token: 't') { :first }
      result = described_class.fetch('k', version_token: 't') { :second }

      expect(result).to eq(:first)
    end

    it 'does not cache when the block raises' do
      calls = 0

      expect do
        described_class.fetch('k', version_token: 't') do
          calls += 1
          raise 'boom'
        end
      end.to raise_error('boom')

      expect do
        described_class.fetch('k', version_token: 't') do
          calls += 1
          :recovered
        end
      end.not_to raise_error

      expect(calls).to eq(2)
    end

    it 'isolates entries by key' do
      described_class.fetch('a', version_token: 't') { :a_value }
      described_class.fetch('b', version_token: 't') { :b_value }

      expect(described_class.fetch('a', version_token: 't') { :unused }).to eq(:a_value)
      expect(described_class.fetch('b', version_token: 't') { :unused }).to eq(:b_value)
    end
  end

  describe '.clear!' do
    it 'wipes all entries so subsequent fetch re-invokes the block' do
      calls = 0
      block = lambda {
        calls += 1
        :value
      }

      described_class.fetch('k', version_token: 't', &block)
      described_class.clear!
      described_class.fetch('k', version_token: 't', &block)

      expect(calls).to eq(2)
    end
  end
end
