# frozen_string_literal: true

require 'yaml'

require 'owl/artifacts/backend'
require 'owl/artifacts/backends/filesystem'

RSpec.describe Owl::Artifacts::Backends::Filesystem do
  def seed_project(root)
    write("#{root}/.owl/artifacts.yaml", Owl::Artifacts::Backends::Filesystem.new(root: nil).default_template)
    Owl::Artifacts::Backends::Filesystem.new(root: nil).seeded_sources.each do |source|
      write("#{root}/#{source[:relative_path]}", source[:contents])
    end
  end

  it 'includes the Owl::Artifacts::Backend contract' do
    expect(described_class.included_modules).to include(Owl::Artifacts::Backend)
  end

  describe 'instance contract' do
    it 'responds to every method declared by Owl::Artifacts::Backend' do
      with_tmp_project do |root|
        backend = described_class.new(root: root)
        Owl::Artifacts::Backend.instance_methods(false).each do |method_name|
          expect(backend).to respond_to(method_name), "missing backend method: #{method_name}"
        end
      end
    end
  end

  describe '#registry' do
    it 'returns Ok with the seven seeded artifact entries on a seeded project' do
      with_tmp_project do |root|
        write("#{root}/.owl/artifacts.yaml", described_class.new(root: nil).default_template)
        result = described_class.new(root: root).registry
        expect(result).to be_ok
        expect(result.value[:entries].map { |e| e[:key] }).to contain_exactly(
          'brief', 'design', 'plan', 'review', 'decomposition', 'verification', 'spec'
        )
      end
    end

    it 'returns Err when the registry file is missing' do
      with_tmp_project do |root|
        result = described_class.new(root: root).registry
        expect(result).to be_err
        expect(result.code).to eq(:artifacts_registry_missing)
      end
    end
  end

  describe '#list' do
    it 'lists seven seeded artifacts with source-present metadata after seed' do
      with_tmp_project do |root|
        seed_project(root)
        result = described_class.new(root: root).list
        expect(result).to be_ok
        expect(result.value.map { |e| e[:key] }).to contain_exactly(
          'brief', 'design', 'plan', 'review', 'decomposition', 'verification', 'spec'
        )
        expect(result.value).to all(include(source_present: true))
      end
    end

    it 'propagates registry errors' do
      with_tmp_project do |root|
        result = described_class.new(root: root).list
        expect(result).to be_err
        expect(result.code).to eq(:artifacts_registry_missing)
      end
    end
  end

  describe '#find' do
    it 'returns Ok with the artifact type body for a registered key' do
      with_tmp_project do |root|
        seed_project(root)
        result = described_class.new(root: root).find(key: 'brief')
        expect(result).to be_ok
        expect(result.value[:body]['id']).to eq('brief')
      end
    end

    it 'returns Err(:unknown_artifact_type) for a missing key' do
      with_tmp_project do |root|
        seed_project(root)
        result = described_class.new(root: root).find(key: 'nope')
        expect(result).to be_err
        expect(result.code).to eq(:unknown_artifact_type)
      end
    end
  end

  describe '#resolve' do
    it 'delegates to TaskArtifactResolver with root, task_id, artifact_key' do
      with_tmp_project do |root|
        backend = described_class.new(root: root)
        sentinel = Owl::Result.ok(key: 'brief', task_id: 'T-001')
        allow(Owl::Artifacts::Internal::TaskArtifactResolver)
          .to receive(:call).with(root: root, task_id: 'T-001', artifact_key: 'brief').and_return(sentinel)
        expect(backend.resolve(task_id: 'T-001', artifact_key: 'brief')).to equal(sentinel)
        expect(Owl::Artifacts::Internal::TaskArtifactResolver)
          .to have_received(:call).with(root: root, task_id: 'T-001', artifact_key: 'brief')
      end
    end
  end

  describe '#scaffold' do
    it 'writes the minimal seed for a new id and returns Ok with path + template_path' do
      with_tmp_project do |root|
        seed_project(root)
        backend = described_class.new(root: root)
        result = backend.scaffold(id: 'sample_at')
        expect(result).to be_ok
        parsed = YAML.safe_load_file(result.value[:path])
        expect(parsed['id']).to eq('sample_at')
        expect(File.exist?(result.value[:template_path])).to be(true)
      end
    end

    it 'refuses to overwrite an existing source without force' do
      with_tmp_project do |root|
        seed_project(root)
        backend = described_class.new(root: root)
        backend.scaffold(id: 'dup_at')
        retry_result = backend.scaffold(id: 'dup_at')
        expect(retry_result).to be_err
        expect(retry_result.code).to eq(:artifact_type_already_exists)
      end
    end

    it 'rejects an invalid id' do
      with_tmp_project do |root|
        seed_project(root)
        result = described_class.new(root: root).scaffold(id: 'Bad-Id')
        expect(result).to be_err
        expect(result.code).to eq(:invalid_artifact_type_id)
      end
    end

    it 'rejects malformed body without creating the file' do
      with_tmp_project do |root|
        seed_project(root)
        result = described_class.new(root: root).scaffold(id: 'noid_at', body: "title: NoId\nkind: markdown\n")
        expect(result).to be_err
        expect(result.code).to eq(:artifact_type_validation_failed)
        expect(File.exist?("#{root}/.owl/artifacts/noid_at/artifact.yaml")).to be(false)
      end
    end
  end

  describe '#validate' do
    it 'validates a registered artifact type by id' do
      with_tmp_project do |root|
        seed_project(root)
        result = described_class.new(root: root).validate(id_or_path: 'brief')
        expect(result).to be_ok
        expect(result.value[:valid]).to be(true)
      end
    end

    it 'returns artifact_type_source_missing for a missing path' do
      with_tmp_project do |root|
        seed_project(root)
        result = described_class.new(root: root).validate(id_or_path: "#{root}/missing.yaml")
        expect(result).to be_err
        expect(result.code).to eq(:artifact_type_source_missing)
      end
    end

    it 'returns unknown_artifact_type for an unregistered id' do
      with_tmp_project do |root|
        seed_project(root)
        result = described_class.new(root: root).validate(id_or_path: 'nope_at')
        expect(result).to be_err
        expect(result.code).to eq(:unknown_artifact_type)
      end
    end
  end

  describe '#default_template' do
    it 'returns a YAML mapping with the seven seeded artifact entries' do
      parsed = YAML.safe_load(described_class.new(root: nil).default_template)
      expect(parsed['artifacts'].keys).to contain_exactly(
        'brief', 'design', 'plan', 'review', 'decomposition', 'verification', 'spec'
      )
    end
  end

  describe '#seeded_sources' do
    it 'returns seven artifact YAMLs and seven Markdown skeletons' do
      sources = described_class.new(root: nil).seeded_sources
      yaml_files = sources.select { |f| f[:relative_path].end_with?('artifact.yaml') }
      markdown_files = sources.select { |f| f[:relative_path].end_with?('templates/default.md') }
      expect(yaml_files.size).to eq(7)
      expect(markdown_files.size).to eq(7)
    end
  end
end
