# frozen_string_literal: true

require 'owl/workflows/api'

RSpec.describe Owl::Workflows::Api do
  describe '.registry' do
    it 'returns Ok with empty entries on a fresh project' do
      with_tmp_project do |root|
        write("#{root}/.owl/workflows.yaml", described_class.default_template)
        result = described_class.registry(root: root)
        expect(result).to be_ok
        expect(result.value[:entries]).to eq([])
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
    it 'returns an empty array on a fresh project' do
      with_tmp_project do |root|
        write("#{root}/.owl/workflows.yaml", described_class.default_template)
        result = described_class.list(root: root)
        expect(result).to be_ok
        expect(result.value).to eq([])
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

  describe '.default_template' do
    it 'creates a parseable YAML with empty workflows map' do
      template = described_class.default_template
      parsed = YAML.safe_load(template)
      expect(parsed['workflows']).to eq({})
      expect(parsed['schema_version']).to eq(1)
    end
  end
end
