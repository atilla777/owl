# frozen_string_literal: true

require 'stringio'
require 'yaml'

require 'owl/cli/api'
require 'owl/tasks/api'

RSpec.describe 'Owl::Tasks::Api.child_create' do
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
        feature_slice:
          enabled: true
          source: "workflows/feature_slice/workflow.yaml"
    YAML
    write("#{root}/.owl/workflows/composite_feature/workflow.yaml",
          "id: composite_feature\nkind: composite_task\nsteps:\n  - id: only\nartifacts: []\n")
    write("#{root}/.owl/workflows/feature_slice/workflow.yaml",
          "id: feature_slice\nkind: task\nsteps:\n  - id: do\nartifacts: []\n")
  end

  it 'creates a child task under a composite parent' do
    with_tmp_project do |root|
      init_with_workflows(root)
      run(['task', 'create', '--workflow', 'composite_feature', '--title', 'P', '--root', root.to_s], cwd: root)

      result = Owl::Tasks::Api.child_create(root: root, parent_id: 'TASK-0001', workflow: 'feature_slice', title: 'C')
      expect(result.ok?).to be(true)
      expect(result.value[:task_id]).to eq('TASK-0002')
      expect(result.value[:payload]['parent_id']).to eq('TASK-0001')
    end
  end

  it 'refuses when parent is not a composite_task' do
    with_tmp_project do |root|
      init_with_workflows(root)
      run(['task', 'create', '--workflow', 'feature_slice', '--title', 'plain', '--root', root.to_s], cwd: root)

      result = Owl::Tasks::Api.child_create(root: root, parent_id: 'TASK-0001', workflow: 'feature_slice', title: 'C')
      expect(result.err?).to be(true)
      expect(result.code).to eq(:parent_not_composite)
    end
  end

  it 'refuses when parent does not exist' do
    with_tmp_project do |root|
      init_with_workflows(root)
      result = Owl::Tasks::Api.child_create(root: root, parent_id: 'TASK-9999', workflow: 'feature_slice', title: 'C')
      expect(result.err?).to be(true)
      expect(result.code).to eq(:task_not_found)
    end
  end

  it 'detects parent_chain_cycle when task.yaml files form a cycle' do
    with_tmp_project do |root|
      init_with_workflows(root)
      run(['task', 'create', '--workflow', 'composite_feature', '--title', 'A', '--root', root.to_s], cwd: root)
      run(
        ['task', 'create', '--workflow', 'composite_feature', '--title', 'B', '--parent', 'TASK-0001', '--root',
         root.to_s], cwd: root
      )
      # Break the index by pointing TASK-0001.parent_id → TASK-0002 (cycle).
      a_path = root + 'tasks/TASK-0001/task.yaml'
      a_payload = YAML.safe_load(a_path.read, aliases: false, permitted_classes: [Time])
      a_payload['parent_id'] = 'TASK-0002'
      a_path.write(YAML.dump(a_payload))

      result = Owl::Tasks::Api.child_create(root: root, parent_id: 'TASK-0002', workflow: 'feature_slice', title: 'C')
      expect(result.err?).to be(true)
      expect(result.code).to eq(:parent_chain_cycle)
    end
  end
end
