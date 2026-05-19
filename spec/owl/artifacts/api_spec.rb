# frozen_string_literal: true

require 'owl/artifacts/api'

RSpec.describe Owl::Artifacts::Api do
  describe '.registry' do
    it 'returns Ok with the twelve seeded artifact entries on a fresh project' do
      with_tmp_project do |root|
        write("#{root}/.owl/artifacts.yaml", described_class.default_template)
        result = described_class.registry(root: root)
        expect(result).to be_ok
        expect(result.value[:entries].map { |e| e[:key] }).to contain_exactly(
          'brief', 'design', 'plan', 'review', 'spec', 'tasks',
          'decomposition', 'verification', 'issue', 'patch_plan',
          'research_findings', 'recommendation'
        )
      end
    end

    it 'returns Err when the registry file is missing' do
      with_tmp_project do |root|
        result = described_class.registry(root: root)
        expect(result).to be_err
        expect(result.code).to eq(:artifacts_registry_missing)
      end
    end

    it 'returns Err when YAML root is not a mapping' do
      with_tmp_project do |root|
        write("#{root}/.owl/artifacts.yaml", "- 1\n- 2\n")
        result = described_class.registry(root: root)
        expect(result).to be_err
        expect(result.code).to eq(:artifacts_registry_invalid)
      end
    end

    it 'returns Err on invalid YAML' do
      with_tmp_project do |root|
        write("#{root}/.owl/artifacts.yaml", ': : :')
        result = described_class.registry(root: root)
        expect(result).to be_err
        expect(result.code).to eq(:artifacts_registry_invalid_yaml)
      end
    end
  end

  describe '.list' do
    it 'returns the twelve seeded artifacts (without source files until init writes them)' do
      with_tmp_project do |root|
        write("#{root}/.owl/artifacts.yaml", described_class.default_template)
        result = described_class.list(root: root)
        expect(result).to be_ok
        expect(result.value.map { |e| e[:key] }).to contain_exactly(
          'brief', 'design', 'plan', 'review', 'spec', 'tasks',
          'decomposition', 'verification', 'issue', 'patch_plan',
          'research_findings', 'recommendation'
        )
        expect(result.value).to all(include(source_present: false))
      end
    end

    it 'includes title and kind from a present source file' do
      with_tmp_project do |root|
        write("#{root}/.owl/artifacts.yaml", <<~YAML)
          schema_version: 1
          artifacts:
            spec:
              source: "artifacts/spec/artifact.yaml"
        YAML

        write("#{root}/.owl/artifacts/spec/artifact.yaml", <<~YAML)
          id: spec
          title: Domain specification
          kind: markdown
          description: Domain spec artifact
        YAML

        result = described_class.list(root: root)
        expect(result).to be_ok
        entry = result.value.first
        expect(entry[:key]).to eq('spec')
        expect(entry[:title]).to eq('Domain specification')
        expect(entry[:kind]).to eq('markdown')
        expect(entry[:description]).to eq('Domain spec artifact')
        expect(entry[:source_present]).to be(true)
      end
    end

    it 'still lists artifacts whose source file is missing' do
      with_tmp_project do |root|
        write("#{root}/.owl/artifacts.yaml", <<~YAML)
          schema_version: 1
          artifacts:
            ghost:
              source: "artifacts/ghost/artifact.yaml"
        YAML

        result = described_class.list(root: root)
        expect(result).to be_ok
        entry = result.value.first
        expect(entry[:key]).to eq('ghost')
        expect(entry[:source_present]).to be(false)
        expect(entry[:title]).to be_nil
      end
    end

    it 'propagates registry errors' do
      with_tmp_project do |root|
        result = described_class.list(root: root)
        expect(result).to be_err
        expect(result.code).to eq(:artifacts_registry_missing)
      end
    end
  end

  describe '.default_template' do
    it 'creates a parseable YAML with the twelve seeded artifact entries' do
      parsed = YAML.safe_load(described_class.default_template)
      expect(parsed['artifacts'].keys).to contain_exactly(
        'brief', 'design', 'plan', 'review', 'spec', 'tasks',
        'decomposition', 'verification', 'issue', 'patch_plan',
        'research_findings', 'recommendation'
      )
      expect(parsed['schema_version']).to eq(1)
      parsed['artifacts'].each_value do |entry|
        expect(entry['source']).to be_a(String)
      end
    end
  end

  describe '.seeded_sources' do
    it 'returns twelve artifact YAMLs + twelve Markdown skeletons' do
      sources = described_class.seeded_sources
      yaml_files = sources.select { |f| f[:relative_path].end_with?('artifact.yaml') }
      markdown_files = sources.select { |f| f[:relative_path].end_with?('templates/default.md') }

      expect(yaml_files.size).to eq(12)
      expect(markdown_files.size).to eq(12)

      yaml_files.each do |file|
        parsed = YAML.safe_load(file[:contents])
        expect(parsed['id']).to be_a(String)
        expect(parsed['kind']).to eq('markdown')
        expect(parsed['default_template']).to eq('templates/default.md')
        expect(parsed.dig('validation', 'required_sections')).to be_an(Array)
      end
    end
  end
end
