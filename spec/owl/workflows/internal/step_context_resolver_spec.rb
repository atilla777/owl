# frozen_string_literal: true

require 'owl/result'
require 'owl/workflows/backends/filesystem'
require 'owl/workflows/internal/step_context_resolver'

RSpec.describe Owl::Workflows::Internal::StepContextResolver do
  let(:source_dir) { '/tmp/owl-fake-workflow-source' }
  let(:backend) { instance_double(Owl::Workflows::Backends::Filesystem) }

  it 'returns Ok with inline context when only `context` is set' do
    result = described_class.call(
      steps: [{ 'id' => 'a', 'context' => 'hi' }],
      backend: backend,
      source_dir: source_dir
    )

    expect(result).to be_ok
    expect(result.value).to eq('a' => 'hi')
  end

  it 'delegates to backend.read_step_context when only `context_file` is set' do
    allow(backend).to receive(:read_step_context).with(
      source_dir: source_dir,
      step_id: 'a',
      relative_path: 'a.context.md'
    ).and_return(Owl::Result.ok('from file'))

    result = described_class.call(
      steps: [{ 'id' => 'a', 'context_file' => 'a.context.md' }],
      backend: backend,
      source_dir: source_dir
    )

    expect(result).to be_ok
    expect(result.value).to eq('a' => 'from file')
  end

  it 'returns Ok with no entries for steps that have neither field' do
    result = described_class.call(
      steps: [{ 'id' => 'a' }, { 'id' => 'b' }],
      backend: backend,
      source_dir: source_dir
    )

    expect(result).to be_ok
    expect(result.value).to eq({})
  end

  it 'returns :step_context_conflict when both fields are set on the same step' do
    result = described_class.call(
      steps: [{ 'id' => 'a', 'context' => 'x', 'context_file' => 'y.md' }],
      backend: backend,
      source_dir: source_dir
    )

    expect(result).to be_err
    expect(result.code).to eq(:step_context_conflict)
    expect(result.details).to eq(step_id: 'a', fields: %w[context context_file])
  end

  it 'returns :invalid_step_context_file when context_file is an empty string' do
    result = described_class.call(
      steps: [{ 'id' => 'a', 'context_file' => '' }],
      backend: backend,
      source_dir: source_dir
    )

    expect(result).to be_err
    expect(result.code).to eq(:invalid_step_context_file)
    expect(result.details).to eq(step_id: 'a', field: 'context_file')
  end

  it 'propagates backend errors verbatim' do
    backend_err = Owl::Result.err(
      code: :step_context_file_not_found,
      message: 'boom',
      details: { step_id: 'a', relative_path: 'a.context.md', resolved_path: '/x/a.context.md' }
    )
    allow(backend).to receive(:read_step_context).and_return(backend_err)

    result = described_class.call(
      steps: [{ 'id' => 'a', 'context_file' => 'a.context.md' }],
      backend: backend,
      source_dir: source_dir
    )

    expect(result).to be(backend_err)
  end

  it 'returns the first conflict when several steps would each be invalid' do
    result = described_class.call(
      steps: [
        { 'id' => 'a', 'context' => 'ok' },
        { 'id' => 'b', 'context' => 'x', 'context_file' => 'y.md' },
        { 'id' => 'c', 'context_file' => 'z.md' }
      ],
      backend: backend,
      source_dir: source_dir
    )

    expect(result).to be_err
    expect(result.code).to eq(:step_context_conflict)
    expect(result.details[:step_id]).to eq('b')
  end

  it 'tolerates symbol-keyed step hashes (matches GraphBuilder behavior)' do
    allow(backend).to receive(:read_step_context).with(
      source_dir: source_dir,
      step_id: 'a',
      relative_path: 'a.context.md'
    ).and_return(Owl::Result.ok('symbol ok'))

    result = described_class.call(
      steps: [{ id: 'a', context_file: 'a.context.md' }],
      backend: backend,
      source_dir: source_dir
    )

    expect(result).to be_ok
    expect(result.value).to eq('a' => 'symbol ok')
  end
end
