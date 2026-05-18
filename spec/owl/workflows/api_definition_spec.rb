# frozen_string_literal: true

require 'owl/workflows/api'

RSpec.describe Owl::Workflows::Api, '.definition' do
  def seed_registry(root)
    write("#{root}/.owl/workflows.yaml", <<~YAML)
      schema_version: 1
      workflows:
        feature:
          enabled: true
          source: "workflows/feature/workflow.yaml"
    YAML
  end

  it 'returns body, normalized step lookup, graph, and artifacts hash' do
    with_tmp_project do |root|
      seed_registry(root)
      write("#{root}/.owl/workflows/feature/workflow.yaml", <<~YAML)
        id: feature
        kind: task
        artifacts:
          brief:
            type: brief
            storage:
              role: tasks
              path: "{{task.id}}/brief.md"
        steps:
          - id: brief
            title: Create brief
            skill: owl.steps.brief
            creates: [brief]
          - id: specify
            requires: [brief]
      YAML

      result = described_class.definition(root: root, workflow_key: 'feature')
      expect(result).to be_ok
      expect(result.value[:key]).to eq('feature')
      expect(result.value[:steps]['brief']['skill']).to eq('owl.steps.brief')
      expect(result.value[:steps]['brief']['creates']).to eq(['brief'])
      expect(result.value[:artifacts]).to include('brief')
      expect(result.value[:graph][:order]).to eq(%w[brief specify])
    end
  end

  it 'returns workflow_source_missing when the source file does not exist' do
    with_tmp_project do |root|
      seed_registry(root)
      result = described_class.definition(root: root, workflow_key: 'feature')
      expect(result).to be_err
      expect(result.code).to eq(:workflow_source_missing)
    end
  end

  it 'propagates unknown_workflow when the key is not in the registry' do
    with_tmp_project do |root|
      seed_registry(root)
      result = described_class.definition(root: root, workflow_key: 'missing')
      expect(result).to be_err
      expect(result.code).to eq(:unknown_workflow)
    end
  end

  it 'propagates graph builder errors (e.g. duplicate_step_id) from the workflow source' do
    with_tmp_project do |root|
      seed_registry(root)
      write("#{root}/.owl/workflows/feature/workflow.yaml", <<~YAML)
        id: feature
        kind: task
        steps:
          - id: a
          - id: a
      YAML

      result = described_class.definition(root: root, workflow_key: 'feature')
      expect(result).to be_err
      expect(result.code).to eq(:duplicate_step_id)
    end
  end

  describe 'per-step context' do
    it 'exposes an inline step.context on the normalized step lookup' do
      with_tmp_project do |root|
        seed_registry(root)
        write("#{root}/.owl/workflows/feature/workflow.yaml", <<~YAML)
          id: feature
          kind: task
          steps:
            - id: a
              context: |
                do X
                then Y
        YAML

        result = described_class.definition(root: root, workflow_key: 'feature')
        expect(result).to be_ok
        expect(result.value[:steps]['a']['context']).to eq("do X\nthen Y\n")
      end
    end

    it 'resolves a step.context_file via the filesystem backend' do
      with_tmp_project do |root|
        seed_registry(root)
        write("#{root}/.owl/workflows/feature/a.context.md", 'from file')
        write("#{root}/.owl/workflows/feature/workflow.yaml", <<~YAML)
          id: feature
          kind: task
          steps:
            - id: a
              context_file: a.context.md
        YAML

        result = described_class.definition(root: root, workflow_key: 'feature')
        expect(result).to be_ok
        expect(result.value[:steps]['a']['context']).to eq('from file')
      end
    end

    it 'returns :step_context_conflict when a step defines both context and context_file' do
      with_tmp_project do |root|
        seed_registry(root)
        write("#{root}/.owl/workflows/feature/workflow.yaml", <<~YAML)
          id: feature
          kind: task
          steps:
            - id: a
              context: inline
              context_file: a.context.md
        YAML

        result = described_class.definition(root: root, workflow_key: 'feature')
        expect(result).to be_err
        expect(result.code).to eq(:step_context_conflict)
        expect(result.details).to eq(step_id: 'a', fields: %w[context context_file])
      end
    end

    it 'returns :step_context_file_not_found when the context_file does not exist' do
      with_tmp_project do |root|
        seed_registry(root)
        write("#{root}/.owl/workflows/feature/workflow.yaml", <<~YAML)
          id: feature
          kind: task
          steps:
            - id: a
              context_file: missing.context.md
        YAML

        result = described_class.definition(root: root, workflow_key: 'feature')
        expect(result).to be_err
        expect(result.code).to eq(:step_context_file_not_found)
        expect(result.details).to include(
          step_id: 'a',
          relative_path: 'missing.context.md'
        )
        expect(result.details[:resolved_path]).to end_with('/.owl/workflows/feature/missing.context.md')
      end
    end

    it 'returns :step_context_path_escape when context_file uses ..' do
      with_tmp_project do |root|
        seed_registry(root)
        write("#{root}/.owl/workflows/feature/workflow.yaml", <<~YAML)
          id: feature
          kind: task
          steps:
            - id: a
              context_file: ../escape.md
        YAML

        result = described_class.definition(root: root, workflow_key: 'feature')
        expect(result).to be_err
        expect(result.code).to eq(:step_context_path_escape)
      end
    end

    it 'returns :invalid_step_context_file when context_file is empty' do
      with_tmp_project do |root|
        seed_registry(root)
        write("#{root}/.owl/workflows/feature/workflow.yaml", <<~YAML)
          id: feature
          kind: task
          steps:
            - id: a
              context_file: ''
        YAML

        result = described_class.definition(root: root, workflow_key: 'feature')
        expect(result).to be_err
        expect(result.code).to eq(:invalid_step_context_file)
        expect(result.details).to eq(step_id: 'a', field: 'context_file')
      end
    end

    it 'uses an injected backend instead of the default filesystem backend' do
      with_tmp_project do |root|
        seed_registry(root)
        write("#{root}/.owl/workflows/feature/workflow.yaml", <<~YAML)
          id: feature
          kind: task
          steps:
            - id: a
              context_file: a.context.md
        YAML

        stub_backend = Class.new do
          def read_step_context(step_id:, relative_path:, **)
            Owl::Result.ok("from stub for #{step_id} / #{relative_path}")
          end
        end.new

        result = described_class.definition(
          root: root,
          workflow_key: 'feature',
          backend: stub_backend
        )

        expect(result).to be_ok
        expect(result.value[:steps]['a']['context']).to eq('from stub for a / a.context.md')
      end
    end
  end
end
