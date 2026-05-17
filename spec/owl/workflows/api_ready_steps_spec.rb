# frozen_string_literal: true

require 'json'
require 'stringio'
require 'yaml'

require 'owl/cli/api'
require 'owl/workflows/api'

RSpec.describe Owl::Workflows::Api, '.ready_steps' do # rubocop:disable RSpec/MultipleDescribes
  def init_project(root)
    stdout = StringIO.new
    stderr = StringIO.new
    Owl::Cli::Api.run(argv: ['init', '--root', root.to_s], stdout: stdout, stderr: stderr, env: {}, cwd: root.to_s)
  end

  def seed_linear_feature_workflow(root)
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
        - id: a
        - id: b
          requires: ["a"]
      artifacts: []
    YAML
  end

  def seed_cyclic_workflow(root)
    write("#{root}/.owl/workflows.yaml", <<~YAML)
      schema_version: 1
      workflows:
        feature:
          enabled: true
          source: "workflows/feature/workflow.yaml"
    YAML
    write("#{root}/.owl/workflows/feature/workflow.yaml", <<~YAML)
      id: feature
      kind: feature
      steps:
        - id: a
          requires: ["b"]
        - id: b
          requires: ["a"]
      artifacts: []
    YAML
  end

  def create_task(root)
    stdout = StringIO.new
    stderr = StringIO.new
    Owl::Cli::Api.run(
      argv: ['task', 'create', '--workflow', 'feature', '--title', 't', '--root', root.to_s, '--json'],
      stdout: stdout, stderr: stderr, env: {}, cwd: root.to_s
    )
    JSON.parse(stdout.string).dig('task', 'id')
  end

  it 'returns the initial ready set after task create' do
    with_tmp_project do |root|
      init_project(root)
      seed_linear_feature_workflow(root)
      task_id = create_task(root)

      result = described_class.ready_steps(root: root, task_id: task_id)
      expect(result).to be_ok
      expect(result.value[:ready].map { |s| s[:id] }).to eq(['a'])
      expect(result.value[:workflow_key]).to eq('feature')
    end
  end

  it 'reports task_not_found when the task does not exist' do
    with_tmp_project do |root|
      init_project(root)
      seed_linear_feature_workflow(root)
      result = described_class.ready_steps(root: root, task_id: 'TASK-9999')
      expect(result).to be_err
      expect(result.code).to eq(:task_not_found)
    end
  end

  it 'reports workflow_source_missing when the source file is gone' do
    with_tmp_project do |root|
      init_project(root)
      seed_linear_feature_workflow(root)
      task_id = create_task(root)
      File.delete("#{root}/.owl/workflows/feature/workflow.yaml")

      result = described_class.ready_steps(root: root, task_id: task_id)
      expect(result).to be_err
      expect(result.code).to eq(:workflow_source_missing)
    end
  end

  it 'propagates workflow_cycle from the graph builder' do
    with_tmp_project do |root|
      init_project(root)
      seed_cyclic_workflow(root)
      task_id = create_task(root)

      result = described_class.ready_steps(root: root, task_id: task_id)
      expect(result).to be_err
      expect(result.code).to eq(:workflow_cycle)
    end
  end

  it 'reports task_workflow_missing when task.yaml has no workflow key' do
    with_tmp_project do |root|
      init_project(root)
      seed_linear_feature_workflow(root)
      task_id = create_task(root)

      path = "#{root}/tasks/#{task_id}/task.yaml"
      payload = YAML.safe_load_file(path, permitted_classes: [Time])
      payload['workflow'].delete('key')
      File.write(path, YAML.dump(payload))

      result = described_class.ready_steps(root: root, task_id: task_id)
      expect(result).to be_err
      expect(result.code).to eq(:task_workflow_missing)
    end
  end
end

RSpec.describe Owl::Workflows::Api, '.graph' do
  def seed(root, workflow_body)
    write("#{root}/.owl/workflows.yaml", <<~YAML)
      schema_version: 1
      workflows:
        feature:
          enabled: true
          source: "workflows/feature/workflow.yaml"
    YAML
    write("#{root}/.owl/workflows/feature/workflow.yaml", workflow_body)
  end

  it 'returns the graph for a registered workflow' do
    with_tmp_project do |root|
      seed(root, "id: feature\nkind: feature\nsteps:\n  - id: a\n  - id: b\n    requires: [\"a\"]\n")
      result = described_class.graph(root: root, workflow_key: 'feature')
      expect(result).to be_ok
      expect(result.value[:order]).to eq(%w[a b])
    end
  end

  it 'returns Err when the workflow is unknown' do
    with_tmp_project do |root|
      seed(root, "id: feature\nkind: feature\n")
      result = described_class.graph(root: root, workflow_key: 'nope')
      expect(result).to be_err
      expect(result.code).to eq(:unknown_workflow)
    end
  end

  it 'returns Err when the workflow source is missing' do
    with_tmp_project do |root|
      write("#{root}/.owl/workflows.yaml", <<~YAML)
        schema_version: 1
        workflows:
          feature:
            enabled: true
            source: "workflows/feature/workflow.yaml"
      YAML
      result = described_class.graph(root: root, workflow_key: 'feature')
      expect(result).to be_err
      expect(result.code).to eq(:workflow_source_missing)
    end
  end
end
