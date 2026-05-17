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
end
