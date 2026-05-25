# frozen_string_literal: true

require 'fileutils'
require 'pathname'
require 'tmpdir'

require 'owl/result'
require 'owl/workflows/backends/filesystem'

RSpec.describe Owl::Workflows::Backends::Filesystem, '#read_step_context_frontmatter' do
  let(:tmpdir) { Pathname.new(Dir.mktmpdir('owl-frontmatter-')) }
  let(:backend) { described_class.new(root: tmpdir.to_s) }
  let(:source_dir) { tmpdir + 'workflows' + 'feature' }

  before { FileUtils.mkdir_p(source_dir.to_s) }
  after { FileUtils.remove_entry_secure(tmpdir.to_s) if tmpdir.exist? }

  it 'returns body + parsed frontmatter when the file has a valid frontmatter block' do
    File.write(source_dir + 'design.context.md', <<~MD)
      ---
      step_id: design
      applies_to_session_type: discussion
      ---

      # Purpose

      Body.
    MD

    result = backend.read_step_context_frontmatter(
      source_dir: source_dir, step_id: 'design', relative_path: 'design.context.md'
    )
    expect(result).to be_ok
    expect(result.value[:frontmatter]).to eq(
      'step_id' => 'design',
      'applies_to_session_type' => 'discussion'
    )
    expect(result.value[:body]).to start_with("\n# Purpose")
  end

  it 'returns empty frontmatter and full body for legacy files without frontmatter' do
    File.write(source_dir + 'design.context.md', "# Purpose\n\nBody.\n")
    result = backend.read_step_context_frontmatter(
      source_dir: source_dir, step_id: 'design', relative_path: 'design.context.md'
    )
    expect(result).to be_ok
    expect(result.value[:frontmatter]).to eq({})
    expect(result.value[:body]).to eq("# Purpose\n\nBody.\n")
  end

  it 'proxies KOS-155 step_context_file_not_found from read_step_context' do
    result = backend.read_step_context_frontmatter(
      source_dir: source_dir, step_id: 'design', relative_path: 'missing.context.md'
    )
    expect(result).to be_err
    expect(result.code).to eq(:step_context_file_not_found)
  end

  it 'proxies KOS-155 step_context_path_escape from read_step_context' do
    result = backend.read_step_context_frontmatter(
      source_dir: source_dir, step_id: 'design', relative_path: '../../etc/passwd'
    )
    expect(result).to be_err
    expect(result.code).to eq(:step_context_path_escape)
  end

  it 'returns Result.err(:step_context_frontmatter_parse_error) for a malformed YAML block' do
    File.write(source_dir + 'design.context.md', "---\nsummary: foo: bar\n---\nbody\n")
    result = backend.read_step_context_frontmatter(
      source_dir: source_dir, step_id: 'design', relative_path: 'design.context.md'
    )
    expect(result).to be_err
    expect(result.code).to eq(:step_context_frontmatter_parse_error)
  end
end
