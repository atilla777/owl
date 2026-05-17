# frozen_string_literal: true

require 'stringio'

require 'owl/cli/api'
require 'owl/tasks/api'

RSpec.describe 'Owl::Tasks::Api.tree' do
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

  it 'builds nested tree from index entries' do
    with_tmp_project do |root|
      init_with_workflows(root)
      run(['task', 'create', '--workflow', 'composite_feature', '--title', 'P', '--root', root.to_s], cwd: root)
      run(
        ['task', 'create', '--workflow', 'feature_slice', '--title', 'C1', '--parent', 'TASK-0001', '--root',
         root.to_s], cwd: root
      )
      run(
        ['task', 'create', '--workflow', 'feature_slice', '--title', 'C2', '--parent', 'TASK-0001', '--root',
         root.to_s], cwd: root
      )
      run(['task', 'create', '--workflow', 'feature_slice', '--title', 'Orphan', '--root', root.to_s], cwd: root)

      result = Owl::Tasks::Api.tree(root: root)
      expect(result.ok?).to be(true)
      ids = result.value[:tasks].map { |n| n[:id] }
      expect(ids).to contain_exactly('TASK-0001', 'TASK-0004')
      parent_node = result.value[:tasks].find { |n| n[:id] == 'TASK-0001' }
      expect(parent_node[:children].map { |c| c[:id] }).to contain_exactly('TASK-0002', 'TASK-0003')
      expect(parent_node[:children].first[:children]).to eq([])
    end
  end

  it 'returns empty tree when no tasks exist' do
    with_tmp_project do |root|
      init_with_workflows(root)
      result = Owl::Tasks::Api.tree(root: root)
      expect(result.ok?).to be(true)
      expect(result.value[:tasks]).to eq([])
    end
  end
end
