# frozen_string_literal: true

require 'pathname'
require 'tmpdir'
require 'json'
require 'fileutils'

require 'owl/result'
require 'owl/validation/internal/schema_check'
require 'owl/workflows/internal/step_context_frontmatter_check'

RSpec.describe Owl::Workflows::Internal::StepContextFrontmatterCheck do
  # Memory backend that returns whatever frontmatter/body we pre-program per
  # relative_path. Real production wires `FrontmatterParser.parse` from
  # `read_step_context`; this spec stubs both methods directly.
  let(:backend) do
    Class.new do
      def initialize(files)
        @files = files
      end

      def read_step_context(source_dir:, step_id:, relative_path:) # rubocop:disable Lint/UnusedMethodArgument
        entry = @files[relative_path]
        return entry if entry.is_a?(Owl::Result::Err)
        return Owl::Result.err(code: :step_context_file_not_found, message: 'missing') if entry.nil?

        # KOS-155 contract returns the raw body string.
        Owl::Result.ok(entry.fetch(:body, ''))
      end

      def read_step_context_frontmatter(source_dir:, step_id:, relative_path:) # rubocop:disable Lint/UnusedMethodArgument
        entry = @files[relative_path]
        return entry if entry.is_a?(Owl::Result::Err)
        return Owl::Result.err(code: :step_context_file_not_found, message: 'missing') if entry.nil?

        Owl::Result.ok(frontmatter: entry.fetch(:frontmatter, {}), body: entry.fetch(:body, ''))
      end
    end
  end

  let(:source_dir) { Pathname.new('/tmp') }

  def file(frontmatter: {}, body: '')
    { frontmatter: frontmatter, body: body }
  end

  describe 'no-op edge cases' do
    it 'skips quietly when backend is nil' do
      result = described_class.call(body: { 'steps' => [] }, backend: nil, source_dir: source_dir)
      expect(result).to be_ok
      expect(result.value).to eq(skipped: true)
    end

    it 'skips quietly when source_dir is nil' do
      result = described_class.call(body: { 'steps' => [] }, backend: backend.new({}), source_dir: nil)
      expect(result).to be_ok
      expect(result.value).to eq(skipped: true)
    end

    it 'returns checked: true with no steps' do
      result = described_class.call(body: {}, backend: backend.new({}), source_dir: source_dir)
      expect(result).to be_ok
      expect(result.value[:checked]).to be(true)
      expect(result.value[:errors]).to eq([])
      expect(result.value[:warnings]).to eq([])
    end
  end

  describe 'KOS-155 short-circuit' do
    it 'silently skips files that KOS-155 already flagged as not_found' do
      body = {
        'steps' => [
          { 'id' => 'design', 'session_type' => 'discussion', 'context_file' => 'design.context.md' }
        ]
      }
      b = backend.new(
        'design.context.md' => Owl::Result.err(
          code: :step_context_file_not_found, message: 'missing'
        )
      )
      result = described_class.call(body: body, backend: b, source_dir: source_dir)
      expect(result).to be_ok
      expect(result.value[:errors]).to eq([])
      expect(result.value[:warnings]).to eq([])
    end

    it 'silently skips files that KOS-155 already flagged as path_escape' do
      body = {
        'steps' => [
          { 'id' => 'design', 'session_type' => 'discussion', 'context_file' => '../../etc/passwd' }
        ]
      }
      b = backend.new(
        '../../etc/passwd' => Owl::Result.err(
          code: :step_context_path_escape, message: 'escape'
        )
      )
      result = described_class.call(body: body, backend: b, source_dir: source_dir)
      expect(result).to be_ok
      expect(result.value[:warnings]).to eq([])
    end
  end

  describe 'missing frontmatter (default :warn under built-in DriftPolicy default)' do
    it 'emits a step_context_frontmatter_missing warning for a body with no frontmatter' do
      body = {
        'steps' => [
          { 'id' => 'design', 'session_type' => 'discussion', 'context_file' => 'design.context.md' }
        ]
      }
      b = backend.new('design.context.md' => file(frontmatter: {}, body: '# Purpose\n'))
      result = described_class.call(body: body, backend: b, source_dir: source_dir)
      expect(result).to be_ok
      expect(result.value[:warnings].size).to eq(1)
      expect(result.value[:warnings].first[:code]).to eq('step_context_frontmatter_missing')
      expect(result.value[:errors]).to eq([])
    end

    it 'silences missing-frontmatter when step has drift_policy: ignore' do
      body = {
        'steps' => [{
          'id' => 'design', 'session_type' => 'discussion',
          'context_file' => 'design.context.md', 'drift_policy' => 'ignore'
        }]
      }
      b = backend.new('design.context.md' => file(frontmatter: {}, body: ''))
      result = described_class.call(body: body, backend: b, source_dir: source_dir)
      expect(result).to be_ok
      expect(result.value[:warnings]).to eq([])
      expect(result.value[:errors]).to eq([])
    end

    it 'escalates missing-frontmatter to an error when step has drift_policy: block' do
      body = {
        'steps' => [{
          'id' => 'design', 'session_type' => 'discussion',
          'context_file' => 'design.context.md', 'drift_policy' => 'block'
        }]
      }
      b = backend.new('design.context.md' => file(frontmatter: {}, body: ''))
      result = described_class.call(body: body, backend: b, source_dir: source_dir)
      expect(result).to be_err
      codes = result.details[:errors].map { |e| e[:code] }
      expect(codes).to eq(['step_context_frontmatter_missing'])
    end
  end

  describe 'field-level checks (criterion #5)' do
    let(:step) do
      {
        'id' => 'design',
        'session_type' => 'discussion',
        'context_file' => 'design.context.md',
        'drift_policy' => 'block'
      }
    end

    it 'reports step_context_frontmatter_step_id_mismatch when frontmatter.step_id != step.id' do
      b = backend.new('design.context.md' => file(frontmatter: { 'step_id' => 'plan' }))
      result = described_class.call(body: { 'steps' => [step] }, backend: b, source_dir: source_dir)
      expect(result).to be_err
      codes = result.details[:errors].map { |e| e[:code] }
      expect(codes).to include('step_context_frontmatter_step_id_mismatch')
    end

    it 'reports step_context_frontmatter_session_type_mismatch when applies_to_session_type differs' do
      b = backend.new(
        'design.context.md' => file(frontmatter: {
                                      'step_id' => 'design',
                                      'applies_to_session_type' => 'execution'
                                    })
      )
      result = described_class.call(body: { 'steps' => [step] }, backend: b, source_dir: source_dir)
      expect(result).to be_err
      codes = result.details[:errors].map { |e| e[:code] }
      expect(codes).to include('step_context_frontmatter_session_type_mismatch')
    end

    it 'reports variants_not_applicable when applies_to_variants is set on a non-variant step' do
      b = backend.new(
        'design.context.md' => file(frontmatter: { 'applies_to_variants' => %w[a b] })
      )
      result = described_class.call(body: { 'steps' => [step] }, backend: b, source_dir: source_dir)
      expect(result).to be_err
      codes = result.details[:errors].map { |e| e[:code] }
      expect(codes).to include('step_context_frontmatter_variants_not_applicable')
    end

    it 'reports step_context_frontmatter_unknown_variant when applies_to_variants includes an unknown key' do
      variant_step = {
        'id' => 'brief', 'session_type' => 'discussion',
        'default_variant' => 'a', 'drift_policy' => 'block',
        'variants' => {
          'a' => { 'context_file' => 'brief.a.context.md' },
          'b' => { 'context_file' => 'brief.b.context.md' }
        }
      }
      b = backend.new(
        'brief.a.context.md' => file(frontmatter: { 'applies_to_variants' => %w[a ghost] }),
        'brief.b.context.md' => file(frontmatter: { 'applies_to_variants' => %w[b] })
      )
      result = described_class.call(body: { 'steps' => [variant_step] }, backend: b, source_dir: source_dir)
      expect(result).to be_err
      codes = result.details[:errors].map { |e| e[:code] }
      expect(codes).to include('step_context_frontmatter_unknown_variant')
    end

    it 'reports step_context_frontmatter_unknown_variant when the file is variant-bound ' \
       'but applies_to_variants omits the actual variant' do
      variant_step = {
        'id' => 'brief', 'session_type' => 'discussion',
        'default_variant' => 'a', 'drift_policy' => 'block',
        'variants' => {
          'a' => { 'context_file' => 'brief.a.context.md' },
          'b' => { 'context_file' => 'brief.b.context.md' }
        }
      }
      # Variant 'a' frontmatter claims it only applies to 'b'.
      b = backend.new(
        'brief.a.context.md' => file(frontmatter: { 'applies_to_variants' => %w[b] }),
        'brief.b.context.md' => file(frontmatter: { 'applies_to_variants' => %w[b] })
      )
      result = described_class.call(body: { 'steps' => [variant_step] }, backend: b, source_dir: source_dir)
      expect(result).to be_err
      paths_for_unknown = result.details[:errors]
                                .select { |e| e[:code] == 'step_context_frontmatter_unknown_variant' }
                                .map { |e| e[:path] }
      expect(paths_for_unknown).to include('/steps/0/variants/a/context_file')
    end

    it 'reports step_context_frontmatter_additional_property for unknown frontmatter keys' do
      b = backend.new(
        'design.context.md' => file(frontmatter: { 'step_id' => 'design', 'unknown_field' => 'x' })
      )
      result = described_class.call(body: { 'steps' => [step] }, backend: b, source_dir: source_dir)
      expect(result).to be_err
      codes = result.details[:errors].map { |e| e[:code] }
      expect(codes).to include('step_context_frontmatter_additional_property')
    end

    it 'accepts a fully consistent frontmatter without errors or warnings' do
      b = backend.new(
        'design.context.md' => file(frontmatter: {
                                      'step_id' => 'design',
                                      'applies_to_session_type' => 'discussion',
                                      'intended_audience' => 'orchestrator',
                                      'summary' => 'Design step'
                                    })
      )
      result = described_class.call(body: { 'steps' => [step] }, backend: b, source_dir: source_dir)
      expect(result).to be_ok
      expect(result.value[:errors]).to eq([])
      expect(result.value[:warnings]).to eq([])
    end
  end

  describe 'KOS-154 local schema override' do
    # Override removes `subagent` from the intended_audience enum.
    let(:tighter_override) do
      JSON.generate(
        'type' => 'object',
        'additionalProperties' => false,
        'properties' => {
          'step_id' => { 'type' => 'string' },
          'intended_audience' => { 'type' => 'string', 'enum' => ['orchestrator'] }
        }
      )
    end

    let(:locked_step) do
      {
        'id' => 'design', 'session_type' => 'discussion',
        'context_file' => 'design.context.md', 'drift_policy' => 'block'
      }
    end

    let(:overriding_frontmatter) do
      { 'step_id' => 'design', 'intended_audience' => 'subagent' }
    end

    around do |example|
      Dir.mktmpdir do |tmp|
        FileUtils.mkdir_p(File.join(tmp, '.owl', 'schemas'))
        File.write(File.join(tmp, '.owl', 'schemas', 'step_context_frontmatter.json'), tighter_override)
        Owl::Validation::Internal::SchemaCheck.reset!
        Dir.chdir(tmp) { example.run }
      ensure
        Owl::Validation::Internal::SchemaCheck.reset!
      end
    end

    it 'tightens the schema when .owl/schemas/step_context_frontmatter.json declares fewer enum values' do
      b = backend.new('design.context.md' => file(frontmatter: overriding_frontmatter))
      result = described_class.call(body: { 'steps' => [locked_step] }, backend: b, source_dir: source_dir)
      expect(result).to be_err
      codes = result.details[:errors].map { |e| e[:code] }
      expect(codes).to include('step_context_frontmatter_schema_violation')
    end
  end
end
