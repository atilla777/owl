# frozen_string_literal: true

require 'owl/workflows/api'

RSpec.describe Owl::Workflows::Api do
  describe '.registry' do
    it 'returns Ok with the six seeded workflow entries on a fresh project' do
      with_tmp_project do |root|
        write("#{root}/.owl/workflows.yaml", described_class.default_template)
        result = described_class.registry(root: root)
        expect(result).to be_ok
        expect(result.value[:entries].map { |e| e[:key] }).to contain_exactly(
          'feature', 'composite_feature', 'feature_slice', 'hotfix', 'research', 'refactor'
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
    it 'returns the six seeded workflows (without source files until init writes them)' do
      with_tmp_project do |root|
        write("#{root}/.owl/workflows.yaml", described_class.default_template)
        result = described_class.list(root: root)
        expect(result).to be_ok
        expect(result.value.map { |e| e[:key] }).to contain_exactly(
          'feature', 'composite_feature', 'feature_slice', 'hotfix', 'research', 'refactor'
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
    it 'creates a parseable YAML with the six seeded workflow entries' do
      template = described_class.default_template
      parsed = YAML.safe_load(template)
      expect(parsed['workflows'].keys).to contain_exactly(
        'feature', 'composite_feature', 'feature_slice', 'hotfix', 'research', 'refactor'
      )
      expect(parsed['default_workflow']).to eq('feature')
      expect(parsed['schema_version']).to eq(1)
      parsed['workflows'].each_value do |entry|
        expect(entry['source']).to be_a(String)
        expect(entry['enabled']).to be(true)
      end
    end
  end

  describe '.seeded_sources' do
    it 'returns six workflow source YAMLs (relative_path + contents)' do
      sources = described_class.seeded_sources
      expect(sources.size).to eq(6)
      expect(sources.map { |f| f[:relative_path] }).to contain_exactly(
        'workflows/feature/workflow.yaml',
        'workflows/composite_feature/workflow.yaml',
        'workflows/feature_slice/workflow.yaml',
        'workflows/hotfix/workflow.yaml',
        'workflows/research/workflow.yaml',
        'workflows/refactor/workflow.yaml'
      )
      sources.each do |file|
        parsed = YAML.safe_load(file[:contents])
        expect(parsed).to be_a(Hash)
        expect(parsed['id']).to be_a(String)
        expect(parsed['kind']).to be_a(String)
        expect(parsed['steps']).to be_an(Array)
      end
    end
  end
end
