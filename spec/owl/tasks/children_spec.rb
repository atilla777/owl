# frozen_string_literal: true

require 'json'
require 'stringio'

require 'owl/cli/api'
require 'owl/tasks/api'

RSpec.describe 'Owl::Tasks::Api.children' do
  def run(argv, cwd:)
    stdout = StringIO.new
    stderr = StringIO.new
    Owl::Cli::Api.run(argv: argv, stdout: stdout, stderr: stderr, env: {}, cwd: cwd.to_s)
    [stdout.string, stderr.string]
  end

  def init_project_with_composite(root)
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
    write("#{root}/.owl/workflows/composite_feature/workflow.yaml", <<~YAML)
      id: composite_feature
      kind: composite_task
      steps:
        - id: only
          skill: owl-step-run
      artifacts: []
    YAML
    write("#{root}/.owl/workflows/feature/workflow.yaml", <<~YAML)
      id: feature
      kind: task
      steps:
        - id: do
          skill: owl-step-run
      artifacts: []
    YAML
  end

  it 'returns children with progress for a composite parent' do
    with_tmp_project do |root|
      init_project_with_composite(root)
      run(['task', 'create', '--workflow', 'composite_feature', '--title', 'p', '--root', root.to_s], cwd: root)
      run(
        ['task', 'create', '--workflow', 'feature', '--title', 'c1', '--parent', 'TASK-0001', '--root',
         root.to_s], cwd: root
      )
      run(
        ['task', 'create', '--workflow', 'feature', '--title', 'c2', '--parent', 'TASK-0001', '--root',
         root.to_s], cwd: root
      )
      run(['step', 'start', 'TASK-0002', 'do', '--root', root.to_s], cwd: root)
      run(['step', 'complete', 'TASK-0002', 'do', '--root', root.to_s], cwd: root)

      result = Owl::Tasks::Api.children(root: root, parent_id: 'TASK-0001')
      expect(result.ok?).to be(true)
      expect(result.value[:parent_id]).to eq('TASK-0001')
      ids = result.value[:children].map { |c| c[:id] }
      expect(ids).to contain_exactly('TASK-0002', 'TASK-0003')
      c1 = result.value[:children].find { |c| c[:id] == 'TASK-0002' }
      expect(c1[:progress]).to eq(done: 1, total: 1, pct: 100.0)
    end
  end

  it 'returns empty children for a non-composite or orphan parent' do
    with_tmp_project do |root|
      init_project_with_composite(root)
      run(['task', 'create', '--workflow', 'feature', '--title', 'plain', '--root', root.to_s], cwd: root)

      result = Owl::Tasks::Api.children(root: root, parent_id: 'TASK-0001')
      expect(result.ok?).to be(true)
      expect(result.value[:children]).to eq([])
    end
  end
end
