# frozen_string_literal: true

require 'json'
require 'stringio'
require 'yaml'

require 'owl/cli/api'
require 'owl/workflows/api'

RSpec.describe Owl::Workflows::Api, '.ready_steps composite children gate' do
  def run(argv, root)
    stdout = StringIO.new
    stderr = StringIO.new
    Owl::Cli::Api.run(argv: argv + ['--root', root.to_s], stdout: stdout, stderr: stderr, env: {}, cwd: root.to_s)
    [stdout.string, stderr.string]
  end

  def seed_workflows(root)
    write("#{root}/.owl/workflows.yaml", <<~YAML)
      schema_version: 1
      workflows:
        composite_feature:
          enabled: true
          source: "workflows/composite_feature/workflow.yaml"
        feature:
          enabled: true
          source: "workflows/feature/workflow.yaml"
    YAML
    write("#{root}/.owl/workflows/composite_feature/workflow.yaml", <<~YAML)
      id: composite_feature
      kind: composite_task
      steps:
        - id: decompose
        - id: review
          requires: [decompose]
        - id: archive
          requires: [review]
          gate: children_complete
      artifacts: []
    YAML
    write("#{root}/.owl/workflows/feature/workflow.yaml", <<~YAML)
      id: feature
      kind: task
      steps:
        - id: do
      artifacts: []
    YAML
  end

  def set_step_status(root, task_id, step_id, status)
    path = "#{root}/tasks/#{task_id}/task.yaml"
    payload = YAML.safe_load_file(path, permitted_classes: [Time])
    payload['steps'].find { |s| s['id'] == step_id }['status'] = status
    File.write(path, YAML.dump(payload))
  end

  def setup_parent_with_child(root)
    run(['init'], root)
    seed_workflows(root)
    run(['task', 'create', '--workflow', 'composite_feature', '--title', 'P'], root)
    run(['task', 'create', '--workflow', 'feature', '--title', 'C', '--parent', 'TASK-0001'], root)
  end

  it 'holds back a gated archive step while a child is in progress' do
    with_tmp_project do |root|
      setup_parent_with_child(root)
      set_step_status(root, 'TASK-0001', 'decompose', 'done')
      set_step_status(root, 'TASK-0001', 'review', 'done')

      result = described_class.ready_steps(root: root, task_id: 'TASK-0001')
      expect(result).to be_ok
      expect(result.value[:ready].map { |s| s[:id] }).not_to include('archive')
      expect(result.value[:blocked_by_children]).to eq(['archive'])
    end
  end

  it 'releases the gated archive step once every child is done' do
    with_tmp_project do |root|
      setup_parent_with_child(root)
      set_step_status(root, 'TASK-0001', 'decompose', 'done')
      set_step_status(root, 'TASK-0001', 'review', 'done')
      run(%w[step start TASK-0002 do], root)
      run(%w[step complete TASK-0002 do], root)

      result = described_class.ready_steps(root: root, task_id: 'TASK-0001')
      expect(result).to be_ok
      expect(result.value[:ready].map { |s| s[:id] }).to eq(['archive'])
      expect(result.value[:blocked_by_children]).to eq([])
    end
  end

  it 'never gates the ungated review step regardless of child progress' do
    with_tmp_project do |root|
      setup_parent_with_child(root)
      set_step_status(root, 'TASK-0001', 'decompose', 'done')

      result = described_class.ready_steps(root: root, task_id: 'TASK-0001')
      expect(result).to be_ok
      expect(result.value[:ready].map { |s| s[:id] }).to eq(['review'])
      expect(result.value[:blocked_by_children]).to eq([])
    end
  end

  it 'ignores the gate flag on a non-composite task' do
    with_tmp_project do |root|
      run(['init'], root)
      write("#{root}/.owl/workflows.yaml", <<~YAML)
        schema_version: 1
        workflows:
          feature:
            enabled: true
            source: "workflows/feature/workflow.yaml"
      YAML
      write("#{root}/.owl/workflows/feature/workflow.yaml", <<~YAML)
        id: feature
        kind: task
        steps:
          - id: a
            gate: children_complete
        artifacts: []
      YAML
      run(['task', 'create', '--workflow', 'feature', '--title', 'plain'], root)

      result = described_class.ready_steps(root: root, task_id: 'TASK-0001')
      expect(result).to be_ok
      expect(result.value[:ready].map { |s| s[:id] }).to eq(['a'])
      expect(result.value[:blocked_by_children]).to eq([])
    end
  end
end
