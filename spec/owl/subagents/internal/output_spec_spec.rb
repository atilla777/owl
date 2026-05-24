# frozen_string_literal: true

require 'owl/subagents/internal/output_spec'

RSpec.describe Owl::Subagents::Internal::OutputSpec do
  let(:valid_body) do
    <<~MD
      ---
      status: returned_normally
      summary: "All good."
      session_type: execution
      ---

      ## Result

      Done.
    MD
  end

  describe '.default' do
    it 'returns required_frontmatter_keys and required_sections' do
      result = described_class.default
      expect(result[:required_frontmatter_keys]).to include('status', 'summary')
      expect(result[:required_sections]).to include('Result')
    end
  end

  describe '.schema (loaded from schemas/step_report.json)' do
    it 'is a frozen Hash with the published JSON Schema shape' do
      schema = described_class.schema
      expect(schema).to be_a(Hash)
      expect(schema).to be_frozen
      expect(schema['$schema']).to eq('https://json-schema.org/draft/2020-12/schema')
      expect(schema['$id']).to eq('https://owl.dev/schemas/step_report/v1.json')
      expect(schema['type']).to eq('object')
    end

    it 'memoizes — repeated reads return the same object' do
      first = described_class.schema
      second = described_class.schema
      expect(first.equal?(second)).to be true
    end

    it 'drives ALLOWED_STATUSES from properties.status.enum' do
      expected = described_class.schema.dig('properties', 'status', 'enum')
      expect(described_class::ALLOWED_STATUSES).to eq(expected)
    end

    it 'drives DEFAULT_REQUIRED_FRONTMATTER_KEYS from required' do
      expect(described_class::DEFAULT_REQUIRED_FRONTMATTER_KEYS).to eq(described_class.schema['required'])
    end

    it 'drives DEFAULT_REQUIRED_SECTIONS from x-required-sections' do
      expect(described_class::DEFAULT_REQUIRED_SECTIONS).to eq(described_class.schema['x-required-sections'])
    end
  end

  describe '.validate' do
    it 'accepts a well-formed body' do
      result = described_class.validate(valid_body)
      expect(result).to be_ok
      expect(result.value[:frontmatter]['status']).to eq('returned_normally')
      expect(result.value[:sections]).to include('Result')
    end

    it 'rejects an empty body' do
      result = described_class.validate('')
      expect(result).to be_err
      expect(result.code).to eq(:report_empty)
    end

    it 'rejects a non-string body' do
      result = described_class.validate(nil)
      expect(result).to be_err
      expect(result.code).to eq(:report_empty)
    end

    it 'rejects a body without frontmatter' do
      result = described_class.validate("# Hello\n")
      expect(result).to be_err
      expect(result.code).to eq(:missing_frontmatter)
    end

    it 'rejects unterminated frontmatter' do
      result = described_class.validate("---\nstatus: returned_normally\n")
      expect(result).to be_err
      expect(result.code).to eq(:unterminated_frontmatter)
    end

    it 'rejects invalid frontmatter YAML' do
      body = "---\nstatus: :::: ::\n---\n\n## Result\n"
      result = described_class.validate(body)
      expect(result).to be_err
      expect(result.code).to eq(:invalid_frontmatter_yaml)
    end

    it 'rejects non-mapping frontmatter' do
      body = "---\n- one\n- two\n---\n\n## Result\n"
      result = described_class.validate(body)
      expect(result).to be_err
      expect(result.code).to eq(:invalid_frontmatter_yaml)
    end

    it 'rejects missing required frontmatter keys' do
      body = "---\nsummary: \"S\"\n---\n\n## Result\n"
      result = described_class.validate(body)
      expect(result).to be_err
      expect(result.code).to eq(:report_invalid)
      paths = result.details[:errors].map { |e| e[:path] }
      expect(paths).to include('frontmatter/status')
    end

    it 'rejects an empty required frontmatter value' do
      body = "---\nstatus: \"\"\nsummary: \"S\"\n---\n\n## Result\n"
      result = described_class.validate(body)
      expect(result).to be_err
      expect(result.code).to eq(:report_invalid)
    end

    it 'rejects an unknown status value' do
      body = "---\nstatus: unicorn\nsummary: \"S\"\n---\n\n## Result\n"
      result = described_class.validate(body)
      expect(result).to be_err
      paths = result.details[:errors].map { |e| e[:path] }
      expect(paths).to include('frontmatter/status')
    end

    it 'rejects missing required sections' do
      body = "---\nstatus: returned_normally\nsummary: \"S\"\n---\n\n## NotResult\n"
      result = described_class.validate(body)
      expect(result).to be_err
      paths = result.details[:errors].map { |e| e[:path] }
      expect(paths).to include('sections/Result')
    end

    it 'accepts a custom output_spec' do
      body = "---\nstatus: returned_normally\nsummary: \"S\"\nextra: yes\n---\n\n## Custom\n"
      result = described_class.validate(
        body,
        output_spec: { required_frontmatter_keys: %w[status extra], required_sections: %w[Custom] }
      )
      expect(result).to be_ok
    end
  end
end
