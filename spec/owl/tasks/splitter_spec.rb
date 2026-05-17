# frozen_string_literal: true

require 'stringio'
require 'yaml'

require 'owl/cli/api'
require 'owl/tasks/api'

RSpec.describe 'Owl::Tasks::Api.split' do
  def run(argv, cwd:)
    stdout = StringIO.new
    stderr = StringIO.new
    Owl::Cli::Api.run(argv: argv, stdout: stdout, stderr: stderr, env: {}, cwd: cwd.to_s)
  end

  def init_with_feature(root)
    run(['init', '--root', root.to_s], cwd: root)
    write("#{root}/.owl/workflows.yaml", <<~YAML)
      schema_version: 1
      workflows:
        feature:
          enabled: true
          source: "workflows/feature/workflow.yaml"
    YAML
    write("#{root}/.owl/workflows/feature/workflow.yaml",
          "id: feature\nkind: task\nsteps:\n  - id: only\nartifacts: []\n")
  end

  it 'flips kind from task to composite_task and rebuilds the index' do
    with_tmp_project do |root|
      init_with_feature(root)
      run(['task', 'create', '--workflow', 'feature', '--title', 'T', '--root', root.to_s], cwd: root)

      result = Owl::Tasks::Api.split(root: root, task_id: 'TASK-0001')
      expect(result.ok?).to be(true)
      expect(result.value[:changed]).to be(true)
      payload = YAML.safe_load((root + 'tasks/TASK-0001/task.yaml').read, aliases: false, permitted_classes: [Time])
      expect(payload['kind']).to eq('composite_task')
      index = YAML.safe_load((root + 'tasks/index.yaml').read, aliases: false, permitted_classes: [Time])
      expect(index['tasks'].first['kind']).to eq('composite_task')
    end
  end

  it 'is idempotent: returns changed: false when already composite_task' do
    with_tmp_project do |root|
      init_with_feature(root)
      run(['task', 'create', '--workflow', 'feature', '--title', 'T', '--root', root.to_s], cwd: root)
      Owl::Tasks::Api.split(root: root, task_id: 'TASK-0001')

      result = Owl::Tasks::Api.split(root: root, task_id: 'TASK-0001')
      expect(result.ok?).to be(true)
      expect(result.value[:changed]).to be(false)
    end
  end

  it 'refuses archived tasks' do
    with_tmp_project do |root|
      init_with_feature(root)
      run(['task', 'create', '--workflow', 'feature', '--title', 'T', '--root', root.to_s], cwd: root)
      path = root + 'tasks/TASK-0001/task.yaml'
      payload = YAML.safe_load(path.read, aliases: false, permitted_classes: [Time])
      payload['status'] = 'archived'
      path.write(YAML.dump(payload))

      result = Owl::Tasks::Api.split(root: root, task_id: 'TASK-0001')
      expect(result.err?).to be(true)
      expect(result.code).to eq(:task_archived)
    end
  end

  it 'returns task_not_found for missing tasks' do
    with_tmp_project do |root|
      init_with_feature(root)
      result = Owl::Tasks::Api.split(root: root, task_id: 'TASK-9999')
      expect(result.err?).to be(true)
      expect(result.code).to eq(:task_not_found)
    end
  end
end
