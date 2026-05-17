# frozen_string_literal: true

require 'json'
require 'stringio'

require 'owl/cli/api'
require 'owl/tasks/api'

RSpec.describe 'Owl::Tasks::Api.parent' do
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

  it 'returns parent payload for a child task' do
    with_tmp_project do |root|
      init_with_workflows(root)
      run(['task', 'create', '--workflow', 'composite_feature', '--title', 'P', '--root', root.to_s], cwd: root)
      run(
        ['task', 'create', '--workflow', 'feature_slice', '--title', 'C', '--parent', 'TASK-0001', '--root',
         root.to_s], cwd: root
      )

      result = Owl::Tasks::Api.parent(root: root, task_id: 'TASK-0002')
      expect(result.ok?).to be(true)
      expect(result.value[:parent][:id]).to eq('TASK-0001')
      expect(result.value[:parent][:kind]).to eq('composite_task')
    end
  end

  it 'returns parent: nil for a top-level task' do
    with_tmp_project do |root|
      init_with_workflows(root)
      run(['task', 'create', '--workflow', 'composite_feature', '--title', 'P', '--root', root.to_s], cwd: root)

      result = Owl::Tasks::Api.parent(root: root, task_id: 'TASK-0001')
      expect(result.ok?).to be(true)
      expect(result.value[:parent]).to be_nil
    end
  end

  it 'returns task_not_found for an unknown task id' do
    with_tmp_project do |root|
      init_with_workflows(root)
      result = Owl::Tasks::Api.parent(root: root, task_id: 'TASK-9999')
      expect(result.err?).to be(true)
      expect(result.code).to eq(:task_not_found)
    end
  end
end
