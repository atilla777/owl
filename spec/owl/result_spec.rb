# frozen_string_literal: true

require 'owl/result'

RSpec.describe Owl::Result do
  describe '.ok' do
    it 'wraps a value in an Ok result' do
      result = described_class.ok(42)

      expect(result).to be_a(described_class::Ok)
      expect(result).to be_ok
      expect(result).not_to be_err
      expect(result.value).to eq(42)
    end
  end

  describe '.err' do
    it 'wraps a structured error with default empty details' do
      result = described_class.err(code: :boom, message: 'kaboom')

      expect(result).to be_a(described_class::Err)
      expect(result).to be_err
      expect(result).not_to be_ok
      expect(result.code).to eq(:boom)
      expect(result.message).to eq('kaboom')
      expect(result.details).to eq({})
    end

    it 'accepts explicit details' do
      result = described_class.err(code: :nope, message: 'why', details: { reason: 'because' })

      expect(result.details).to eq(reason: 'because')
    end
  end
end
