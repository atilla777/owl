# frozen_string_literal: true

require 'json'
require 'stringio'

require 'owl/cli/internal/json_printer'

RSpec.describe Owl::Cli::Internal::JsonPrinter do
  let(:stderr) { StringIO.new }

  describe '.failure (default error_class)' do
    it 'returns exit code 1 (validation)' do
      exit_code = described_class.failure(stderr, code: :bad_args, message: 'nope')
      expect(exit_code).to eq(1)
    end

    it 'writes error_class: "validation" into the payload' do
      described_class.failure(stderr, code: :bad_args, message: 'nope')
      payload = JSON.parse(stderr.string)
      expect(payload.dig('error', 'error_class')).to eq('validation')
      expect(payload.dig('error', 'code')).to eq('bad_args')
    end
  end

  describe '.failure with explicit error_class' do
    it 'maps :recoverable to exit 2' do
      exit_code = described_class.failure(
        stderr, code: :drift_block, message: 'drift', error_class: :recoverable
      )
      expect(exit_code).to eq(2)
      payload = JSON.parse(stderr.string)
      expect(payload.dig('error', 'error_class')).to eq('recoverable')
    end

    it 'maps :fatal to exit 3' do
      exit_code = described_class.failure(
        stderr, code: :schema_missing, message: 'gem broken', error_class: :fatal
      )
      expect(exit_code).to eq(3)
      payload = JSON.parse(stderr.string)
      expect(payload.dig('error', 'error_class')).to eq('fatal')
    end

    it 'raises ArgumentError for unknown error_class' do
      expect do
        described_class.failure(stderr, code: :x, message: 'y', error_class: :no_such_class)
      end.to raise_error(ArgumentError, /Unknown error_class/)
    end
  end

  describe '.failure payload structure' do
    it 'contains code, message, error_class, details' do
      described_class.failure(
        stderr, code: :x, message: 'm', details: { foo: 'bar' }, error_class: :recoverable
      )
      payload = JSON.parse(stderr.string)
      expect(payload['ok']).to be(false)
      expect(payload['error'].keys).to include('code', 'message', 'error_class', 'details')
      expect(payload.dig('error', 'details', 'foo')).to eq('bar')
    end
  end

  describe '::EXIT_CODES' do
    it 'maps the four classes to their canonical exit codes' do
      expect(described_class::EXIT_CODES).to eq(
        validation: 1, recoverable: 2, fatal: 3, step_context_frontmatter: 4
      )
    end

    it 'is frozen' do
      expect(described_class::EXIT_CODES).to be_frozen
    end
  end

  describe '.failure with :step_context_frontmatter error_class (KOS-156)' do
    it 'maps :step_context_frontmatter to exit 4' do
      exit_code = described_class.failure(
        stderr,
        code: :workflow_validation_failed,
        message: 'frontmatter contract violation',
        details: { source: 'step_context_frontmatter', errors: [] },
        error_class: :step_context_frontmatter
      )
      expect(exit_code).to eq(4)
      payload = JSON.parse(stderr.string)
      expect(payload.dig('error', 'error_class')).to eq('step_context_frontmatter')
    end
  end
end
