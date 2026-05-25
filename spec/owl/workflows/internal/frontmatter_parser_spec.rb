# frozen_string_literal: true

require 'owl/result'
require 'owl/workflows/internal/frontmatter_parser'

RSpec.describe Owl::Workflows::Internal::FrontmatterParser do
  describe '.parse' do
    it 'returns ok with empty frontmatter and full body for text without a leading frontmatter block' do
      result = described_class.parse("# Heading\n\nbody text\n")
      expect(result).to be_ok
      expect(result.value[:frontmatter]).to eq({})
      expect(result.value[:body]).to eq("# Heading\n\nbody text\n")
    end

    it 'splits a well-formed frontmatter block from the markdown body' do
      text = <<~MD
        ---
        step_id: design
        applies_to_session_type: discussion
        ---

        # Purpose

        Body text.
      MD
      result = described_class.parse(text)
      expect(result).to be_ok
      expect(result.value[:frontmatter]).to eq(
        'step_id' => 'design',
        'applies_to_session_type' => 'discussion'
      )
      expect(result.value[:body]).to start_with("\n# Purpose")
    end

    it 'parses only the first ---/--- block when a second one appears in the body' do
      text = "---\nstep_id: design\n---\n\n## Section\n\n---\nother: thing\n---\nmore\n"
      result = described_class.parse(text)
      expect(result).to be_ok
      expect(result.value[:frontmatter]).to eq('step_id' => 'design')
      expect(result.value[:body]).to include('## Section').and include('other: thing')
    end

    it 'returns Result.err(:step_context_frontmatter_unterminated) when the closing --- is missing' do
      text = "---\nstep_id: design\nno_closing_marker\n"
      result = described_class.parse(text)
      expect(result).to be_err
      expect(result.code).to eq(:step_context_frontmatter_unterminated)
    end

    it 'returns Result.err(:step_context_frontmatter_parse_error) on YAML syntax errors' do
      # `summary: foo: bar` without quoting is a documented YAML pitfall (knowledge #44).
      text = "---\nsummary: foo: bar\n---\nbody\n"
      result = described_class.parse(text)
      expect(result).to be_err
      expect(result.code).to eq(:step_context_frontmatter_parse_error)
    end

    it 'returns Result.err(:step_context_frontmatter_invalid_root) when frontmatter root is not a mapping' do
      text = "---\n- one\n- two\n---\nbody\n"
      result = described_class.parse(text)
      expect(result).to be_err
      expect(result.code).to eq(:step_context_frontmatter_invalid_root)
    end

    it 'returns ok with an empty body when the frontmatter block ends at end-of-file' do
      text = "---\nstep_id: design\n---\n"
      result = described_class.parse(text)
      expect(result).to be_ok
      expect(result.value[:frontmatter]).to eq('step_id' => 'design')
      expect(result.value[:body]).to eq('')
    end

    it 'coerces nil input to empty string and returns empty frontmatter' do
      result = described_class.parse(nil)
      expect(result).to be_ok
      expect(result.value[:frontmatter]).to eq({})
      expect(result.value[:body]).to eq('')
    end
  end
end
