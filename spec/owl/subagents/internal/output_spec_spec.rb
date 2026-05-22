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
