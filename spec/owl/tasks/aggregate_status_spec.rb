# frozen_string_literal: true

require 'stringio'
require 'yaml'

require 'owl/cli/api'
require 'owl/tasks/api'

RSpec.describe 'Owl::Tasks::Api.aggregate_status' do
  def run(argv, cwd:)
    stdout = StringIO.new
    stderr = StringIO.new
    Owl::Cli::Api.run(argv: argv, stdout: stdout, stderr: stderr, env: {}, cwd: cwd.to_s)
  end

  def init_with_workflows(root)
    run(['init', '--root', root.to_s], cwd: root)
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
    write("#{root}/.owl/workflows/composite_feature/workflow.yaml",
          "id: composite_feature\nkind: composite_task\nsteps:\n  - id: only\nartifacts: []\n")
    write("#{root}/.owl/workflows/feature/workflow.yaml",
          "id: feature\nkind: task\nsteps:\n  - id: do\nartifacts: []\n")
  end

  def set_child_step_status(root, task_id, step_id, status)
    path = root + "tasks/#{task_id}/task.yaml"
    payload = YAML.safe_load(path.read, aliases: false, permitted_classes: [Time])
    step = payload['steps'].find { |s| s['id'] == step_id }
    step['status'] = status
    path.write(YAML.dump(payload))
  end

  it 'returns open when at least one child is in progress' do
    with_tmp_project do |root|
      init_with_workflows(root)
      run(['task', 'create', '--workflow', 'composite_feature', '--title', 'P', '--root', root.to_s], cwd: root)
      run(
        ['task', 'create', '--workflow', 'feature', '--title', 'C', '--parent', 'TASK-0001', '--root',
         root.to_s], cwd: root
      )

      result = Owl::Tasks::Api.aggregate_status(root: root, task_id: 'TASK-0001')
      expect(result.ok?).to be(true)
      expect(result.value[:aggregate]).to eq('open')
      expect(result.value[:by_state]).to include('in_progress' => 1)
    end
  end

  it 'returns blocked when a child has a blocked step' do
    with_tmp_project do |root|
      init_with_workflows(root)
      run(['task', 'create', '--workflow', 'composite_feature', '--title', 'P', '--root', root.to_s], cwd: root)
      run(
        ['task', 'create', '--workflow', 'feature', '--title', 'C', '--parent', 'TASK-0001', '--root',
         root.to_s], cwd: root
      )
      set_child_step_status(root, 'TASK-0002', 'do', 'blocked')

      result = Owl::Tasks::Api.aggregate_status(root: root, task_id: 'TASK-0001')
      expect(result.ok?).to be(true)
      expect(result.value[:aggregate]).to eq('blocked')
    end
  end

  it 'returns ready when all children done but not archived' do
    with_tmp_project do |root|
      init_with_workflows(root)
      run(['task', 'create', '--workflow', 'composite_feature', '--title', 'P', '--root', root.to_s], cwd: root)
      run(
        ['task', 'create', '--workflow', 'feature', '--title', 'C', '--parent', 'TASK-0001', '--root',
         root.to_s], cwd: root
      )
      run(['step', 'start', 'TASK-0002', 'do', '--root', root.to_s], cwd: root)
      run(['step', 'complete', 'TASK-0002', 'do', '--root', root.to_s], cwd: root)

      result = Owl::Tasks::Api.aggregate_status(root: root, task_id: 'TASK-0001')
      expect(result.ok?).to be(true)
      expect(result.value[:aggregate]).to eq('ready')
    end
  end

  it 'returns not_a_composite_task error for plain tasks' do
    with_tmp_project do |root|
      init_with_workflows(root)
      run(['task', 'create', '--workflow', 'feature', '--title', 'plain', '--root', root.to_s], cwd: root)

      result = Owl::Tasks::Api.aggregate_status(root: root, task_id: 'TASK-0001')
      expect(result.err?).to be(true)
      expect(result.code).to eq(:not_a_composite_task)
    end
  end
end
