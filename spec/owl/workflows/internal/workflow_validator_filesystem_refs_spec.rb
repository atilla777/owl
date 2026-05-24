# frozen_string_literal: true

require 'pathname'

require 'owl/result'
require 'owl/workflows/internal/workflow_validator'

RSpec.describe Owl::Workflows::Internal::WorkflowValidator, '.validate_filesystem_refs' do
  ok_backend = Class.new do
    def read_step_context(source_dir:, step_id:, relative_path:) # rubocop:disable Lint/UnusedMethodArgument
      Owl::Result.ok(content: 'ok')
    end
  end

  missing_file_backend = Class.new do
    def read_step_context(source_dir:, step_id:, relative_path:)
      Owl::Result.err(
        code: :step_context_file_not_found,
        message: "Step '#{step_id}' context_file '#{relative_path}' not found.",
        details: { step_id: step_id, relative_path: relative_path }
      )
    end
  end

  escape_backend = Class.new do
    def read_step_context(source_dir:, step_id:, relative_path:)
      Owl::Result.err(
        code: :step_context_path_escape,
        message: "Step '#{step_id}' context_file '#{relative_path}' escapes the workflow source directory.",
        details: { step_id: step_id, relative_path: relative_path }
      )
    end
  end

  let(:step_with_context_file) do
    {
      'steps' => [
        { 'id' => 'main', 'session_type' => 'discussion', 'context_file' => 'main.md' }
      ]
    }
  end

  let(:step_with_variants) do
    {
      'steps' => [
        {
          'id' => 'brief',
          'session_type' => 'discussion',
          'default_variant' => 'a',
          'variants' => {
            'a' => { 'context_file' => 'a.md' },
            'b' => { 'context_file' => 'b.md' }
          }
        }
      ]
    }
  end

  it 'skips quietly when backend is nil' do
    result = described_class.validate_filesystem_refs(
      body: step_with_context_file, backend: nil, source_dir: Pathname.new('/tmp')
    )
    expect(result).to be_ok
    expect(result.value).to eq(skipped: true)
  end

  it 'skips quietly when source_dir is nil' do
    result = described_class.validate_filesystem_refs(
      body: step_with_context_file, backend: ok_backend.new, source_dir: nil
    )
    expect(result).to be_ok
    expect(result.value).to eq(skipped: true)
  end

  it 'returns ok when backend reports every context file ok' do
    result = described_class.validate_filesystem_refs(
      body: step_with_variants, backend: ok_backend.new, source_dir: Pathname.new('/tmp')
    )
    expect(result).to be_ok
    expect(result.value).to eq(checked: true)
  end

  it 'reports missing step-level context_file with the /steps/<idx>/context_file locator' do
    result = described_class.validate_filesystem_refs(
      body: step_with_context_file, backend: missing_file_backend.new, source_dir: Pathname.new('/tmp')
    )
    expect(result).to be_err
    errors = result.details[:errors]
    expect(errors.map { |e| e[:path] }).to eq(['/steps/0/context_file'])
    expect(errors.first[:code]).to eq('step_context_file_not_found')
  end

  it 'reports missing variant context_file with the /steps/<idx>/variants/<name>/context_file locator' do
    result = described_class.validate_filesystem_refs(
      body: step_with_variants, backend: missing_file_backend.new, source_dir: Pathname.new('/tmp')
    )
    expect(result).to be_err
    paths = result.details[:errors].map { |e| e[:path] }
    expect(paths).to contain_exactly(
      '/steps/0/variants/a/context_file',
      '/steps/0/variants/b/context_file'
    )
  end

  it 'reports escape attempts via the same locator shape' do
    body = {
      'steps' => [
        { 'id' => 'main', 'session_type' => 'discussion', 'context_file' => '../../etc/passwd' }
      ]
    }
    result = described_class.validate_filesystem_refs(
      body: body, backend: escape_backend.new, source_dir: Pathname.new('/tmp')
    )
    expect(result).to be_err
    err = result.details[:errors].first
    expect(err[:path]).to eq('/steps/0/context_file')
    expect(err[:code]).to eq('step_context_path_escape')
  end

  it 'ignores steps with variants when checking step-level context_file' do
    body = {
      'steps' => [{
        'id' => 'brief',
        'session_type' => 'discussion',
        'context_file' => 'unused.md',
        'default_variant' => 'a',
        'variants' => { 'a' => { 'context_file' => 'a.md' } }
      }]
    }
    backend = Class.new do
      attr_reader :calls

      def initialize
        @calls = []
      end

      def read_step_context(source_dir:, step_id:, relative_path:)
        @calls << relative_path
        Owl::Result.ok(content: 'ok')
      end
    end.new

    described_class.validate_filesystem_refs(
      body: body, backend: backend, source_dir: Pathname.new('/tmp')
    )

    expect(backend.calls).to eq(['a.md'])
  end

  it 'skips steps without id or with non-mapping shapes' do
    body = {
      'steps' => [
        nil,
        { 'id' => '', 'context_file' => 'x.md' },
        { 'id' => 'real', 'session_type' => 'discussion' }
      ]
    }
    result = described_class.validate_filesystem_refs(
      body: body, backend: missing_file_backend.new, source_dir: Pathname.new('/tmp')
    )
    expect(result).to be_ok
  end
end
