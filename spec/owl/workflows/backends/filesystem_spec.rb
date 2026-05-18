# frozen_string_literal: true

require 'owl/workflows/backend'
require 'owl/workflows/backends/filesystem'

RSpec.describe Owl::Workflows::Backends::Filesystem do
  it 'includes the Owl::Workflows::Backend contract' do
    expect(described_class.included_modules).to include(Owl::Workflows::Backend)
  end

  it 'responds to read_step_context' do
    with_tmp_project do |root|
      backend = described_class.new(root: root)
      expect(backend).to respond_to(:read_step_context)
    end
  end

  describe '#read_step_context' do
    it 'returns Ok with file contents when context_file exists inside the workflow source directory' do
      with_tmp_project do |root|
        source_dir = "#{root}/.owl/workflows/feature"
        write("#{source_dir}/specify.context.md", 'hello from file')
        backend = described_class.new(root: root)

        result = backend.read_step_context(
          source_dir: source_dir,
          step_id: 'specify',
          relative_path: 'specify.context.md'
        )

        expect(result).to be_ok
        expect(result.value).to eq('hello from file')
      end
    end

    it 'returns :step_context_file_not_found when the relative file is missing' do
      with_tmp_project do |root|
        source_dir = "#{root}/.owl/workflows/feature"
        FileUtils.mkdir_p(source_dir)
        backend = described_class.new(root: root)

        result = backend.read_step_context(
          source_dir: source_dir,
          step_id: 'specify',
          relative_path: 'missing.context.md'
        )

        expect(result).to be_err
        expect(result.code).to eq(:step_context_file_not_found)
        expect(result.details).to include(
          step_id: 'specify',
          relative_path: 'missing.context.md'
        )
        expect(result.details[:resolved_path]).to end_with('/.owl/workflows/feature/missing.context.md')
      end
    end

    it 'returns :step_context_path_escape when the relative path uses ..' do
      with_tmp_project do |root|
        source_dir = "#{root}/.owl/workflows/feature"
        FileUtils.mkdir_p(source_dir)
        backend = described_class.new(root: root)

        result = backend.read_step_context(
          source_dir: source_dir,
          step_id: 'specify',
          relative_path: '../other/secret.md'
        )

        expect(result).to be_err
        expect(result.code).to eq(:step_context_path_escape)
        expect(result.details).to eq(
          step_id: 'specify',
          relative_path: '../other/secret.md'
        )
      end
    end

    it 'returns :step_context_path_escape when the relative path is absolute' do
      with_tmp_project do |root|
        source_dir = "#{root}/.owl/workflows/feature"
        FileUtils.mkdir_p(source_dir)
        backend = described_class.new(root: root)

        result = backend.read_step_context(
          source_dir: source_dir,
          step_id: 'specify',
          relative_path: '/etc/passwd'
        )

        expect(result).to be_err
        expect(result.code).to eq(:step_context_path_escape)
      end
    end
  end
end
