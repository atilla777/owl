# frozen_string_literal: true

require 'owl/workflows/api'

RSpec.describe Owl::Workflows::Api do
  describe '.registry' do
    it 'returns Ok with the two seeded workflow entries on a fresh project' do
      with_tmp_project do |root|
        write("#{root}/.owl/workflows.yaml", described_class.default_template)
        result = described_class.registry(root: root)
        expect(result).to be_ok
        expect(result.value[:entries].map { |e| e[:key] }).to contain_exactly(
          'feature', 'composite_feature'
        )
        expect(result.value[:schema_version]).to eq(1)
      end
    end

    it 'returns Err when the registry file is missing' do
      with_tmp_project do |root|
        result = described_class.registry(root: root)
        expect(result).to be_err
        expect(result.code).to eq(:workflows_registry_missing)
      end
    end

    it 'returns Err when YAML root is not a mapping' do
      with_tmp_project do |root|
        write("#{root}/.owl/workflows.yaml", "- one\n- two\n")
        result = described_class.registry(root: root)
        expect(result).to be_err
        expect(result.code).to eq(:workflows_registry_invalid)
      end
    end

    it 'returns Err on invalid YAML' do
      with_tmp_project do |root|
        write("#{root}/.owl/workflows.yaml", ': : :')
        result = described_class.registry(root: root)
        expect(result).to be_err
        expect(result.code).to eq(:workflows_registry_invalid_yaml)
      end
    end
  end

  describe '.list' do
    it 'returns the two seeded workflows (without source files until init writes them)' do
      with_tmp_project do |root|
        write("#{root}/.owl/workflows.yaml", described_class.default_template)
        result = described_class.list(root: root)
        expect(result).to be_ok
        expect(result.value.map { |e| e[:key] }).to contain_exactly(
          'feature', 'composite_feature'
        )
        expect(result.value).to all(include(source_present: false))
      end
    end

    it 'includes description and kind from a present source file' do
      with_tmp_project do |root|
        write("#{root}/.owl/workflows.yaml", <<~YAML)
          schema_version: 1
          workflows:
            feature:
              enabled: true
              source: "workflows/feature/workflow.yaml"
              title: "Feature development"
              aliases: ["feature", "story"]
              priority: 50
              version: "1.0"
        YAML

        write("#{root}/.owl/workflows/feature/workflow.yaml", <<~YAML)
          id: feature
          kind: task
          title: Feature development
          description: "Standard feature workflow"
        YAML

        result = described_class.list(root: root)
        expect(result).to be_ok
        entry = result.value.first
        expect(entry[:key]).to eq('feature')
        expect(entry[:description]).to eq('Standard feature workflow')
        expect(entry[:kind]).to eq('task')
        expect(entry[:source_present]).to be(true)
        expect(entry[:enabled]).to be(true)
        expect(entry[:aliases]).to eq(%w[feature story])
      end
    end

    it 'still lists workflows whose source file is missing' do
      with_tmp_project do |root|
        write("#{root}/.owl/workflows.yaml", <<~YAML)
          schema_version: 1
          workflows:
            ghost:
              enabled: true
              source: "workflows/ghost/workflow.yaml"
              title: "Ghost"
        YAML

        result = described_class.list(root: root)
        expect(result).to be_ok
        entry = result.value.first
        expect(entry[:key]).to eq('ghost')
        expect(entry[:source_present]).to be(false)
        expect(entry[:description]).to be_nil
        expect(entry[:kind]).to be_nil
      end
    end

    it 'propagates registry errors' do
      with_tmp_project do |root|
        result = described_class.list(root: root)
        expect(result).to be_err
        expect(result.code).to eq(:workflows_registry_missing)
      end
    end
  end

  describe '.find' do
    it 'returns Ok with entry and source body when the key is registered and source exists' do
      with_tmp_project do |root|
        write("#{root}/.owl/workflows.yaml", <<~YAML)
          schema_version: 1
          workflows:
            feature:
              enabled: true
              source: "workflows/feature/workflow.yaml"
              version: "1.0"
        YAML
        write("#{root}/.owl/workflows/feature/workflow.yaml", <<~YAML)
          id: feature
          kind: feature
          steps:
            - id: noop
        YAML

        result = described_class.find(root: root, key: 'feature')
        expect(result).to be_ok
        expect(result.value[:entry][:key]).to eq('feature')
        expect(result.value[:source][:body]['kind']).to eq('feature')
        expect(result.value[:source][:body]['steps']).to be_an(Array)
      end
    end

    it 'returns Err(:unknown_workflow) when the key is missing and lists known keys' do
      with_tmp_project do |root|
        write("#{root}/.owl/workflows.yaml", <<~YAML)
          schema_version: 1
          workflows:
            feature:
              source: "workflows/feature.yaml"
        YAML
        result = described_class.find(root: root, key: 'nope')
        expect(result).to be_err
        expect(result.code).to eq(:unknown_workflow)
        expect(result.details[:available]).to eq(['feature'])
      end
    end

    it 'propagates registry errors' do
      with_tmp_project do |root|
        result = described_class.find(root: root, key: 'feature')
        expect(result).to be_err
        expect(result.code).to eq(:workflows_registry_missing)
      end
    end
  end

  describe '.default_template' do
    it 'creates a parseable YAML with the two seeded workflow entries' do
      template = described_class.default_template
      parsed = YAML.safe_load(template)
      expect(parsed['workflows'].keys).to contain_exactly(
        'feature', 'composite_feature'
      )
      expect(parsed['default_workflow']).to eq('feature')
      expect(parsed['schema_version']).to eq(1)
      parsed['workflows'].each_value do |entry|
        expect(entry['source']).to be_a(String)
        expect(entry['enabled']).to be(true)
      end
    end
  end

  describe '.resolve_backend' do
    it 'returns a Filesystem backend when no config file is present' do
      with_tmp_project do |root|
        backend = described_class.resolve_backend(root: root)
        expect(backend).to be_a(Owl::Workflows::Backends::Filesystem)
      end
    end

    it 'returns a Filesystem backend when settings.storage.backend is "filesystem"' do
      with_tmp_project do |root|
        write("#{root}/.owl/config.yaml", <<~YAML)
          settings:
            storage:
              backend: filesystem
        YAML

        backend = described_class.resolve_backend(root: root)
        expect(backend).to be_a(Owl::Workflows::Backends::Filesystem)
      end
    end

    it 'returns a Filesystem backend when config.yaml has no settings hash' do
      with_tmp_project do |root|
        write("#{root}/.owl/config.yaml", "irrelevant: true\n")
        backend = described_class.resolve_backend(root: root)
        expect(backend).to be_a(Owl::Workflows::Backends::Filesystem)
      end
    end

    it 'returns a Filesystem backend when settings.storage is not a hash' do
      with_tmp_project do |root|
        write("#{root}/.owl/config.yaml", <<~YAML)
          settings:
            storage: "literal"
        YAML
        backend = described_class.resolve_backend(root: root)
        expect(backend).to be_a(Owl::Workflows::Backends::Filesystem)
      end
    end

    it 'returns a Filesystem backend when settings.storage.backend is blank' do
      with_tmp_project do |root|
        write("#{root}/.owl/config.yaml", <<~YAML)
          settings:
            storage:
              backend: ""
        YAML
        backend = described_class.resolve_backend(root: root)
        expect(backend).to be_a(Owl::Workflows::Backends::Filesystem)
      end
    end

    it 'returns a Filesystem backend when config.yaml is YAML-invalid (rescued)' do
      with_tmp_project do |root|
        write("#{root}/.owl/config.yaml", ": : :\n")
        backend = described_class.resolve_backend(root: root)
        expect(backend).to be_a(Owl::Workflows::Backends::Filesystem)
      end
    end

    it 'returns a Filesystem backend when YAML root is not a hash' do
      with_tmp_project do |root|
        write("#{root}/.owl/config.yaml", "- one\n- two\n")
        backend = described_class.resolve_backend(root: root)
        expect(backend).to be_a(Owl::Workflows::Backends::Filesystem)
      end
    end

    it 'raises UnknownBackendError for an unknown backend name' do
      with_tmp_project do |root|
        write("#{root}/.owl/config.yaml", <<~YAML)
          settings:
            storage:
              backend: imaginary
        YAML

        expect do
          described_class.resolve_backend(root: root)
        end.to raise_error(Owl::Workflows::UnknownBackendError, /imaginary/)
      end
    end
  end

  describe '.seeded_sources' do
    it 'returns two workflow source YAMLs (relative_path + contents)' do
      sources = described_class.seeded_sources
      workflow_files = sources.select { |f| f[:relative_path].end_with?('/workflow.yaml') }
      expect(workflow_files.size).to eq(2)
      expect(workflow_files.map { |f| f[:relative_path] }).to contain_exactly(
        '.owl/workflows/feature/workflow.yaml',
        '.owl/workflows/composite_feature/workflow.yaml'
      )
      workflow_files.each do |file|
        parsed = YAML.safe_load(file[:contents])
        expect(parsed).to be_a(Hash)
        expect(parsed['id']).to be_a(String)
        expect(parsed['kind']).to be_a(String)
        expect(parsed['steps']).to be_an(Array)
      end
    end

    it 'returns per-step .context.md files alongside every seeded workflow' do
      sources = described_class.seeded_sources
      context_files = sources.select { |f| f[:relative_path].end_with?('.context.md') }
      expect(context_files).not_to be_empty
      context_files.each do |file|
        # Accepts both `<step_id>.context.md` and `<step_id>.<variant>.context.md`.
        expect(file[:relative_path]).to match(%r{\A\.owl/workflows/[^/]+/[a-z_]+(?:\.[a-z_]+)?\.context\.md\z}),
                                        -> { "unexpected context path: #{file[:relative_path]}" }
        expect(file[:contents]).to include('# Purpose')
      end
    end
  end
end
