# frozen_string_literal: true

require 'stringio'
require 'yaml'

require 'owl/cli/api'
require 'owl/tasks/api'

RSpec.describe 'Owl::Tasks::Api.index_drift' do
  def cli(argv, root)
    Owl::Cli::Api.run(argv: argv, stdout: StringIO.new, stderr: StringIO.new, env: {}, cwd: root.to_s)
  end

  def setup_project(root)
    cli(['init', '--root', root.to_s], root)
    write("#{root}/.owl/workflows.yaml", <<~YAML)
      schema_version: 1
      workflows:
        quick:
          enabled: true
          source: "workflows/quick/workflow.yaml"
    YAML
    write("#{root}/.owl/workflows/quick/workflow.yaml", <<~YAML)
      id: quick
      kind: task
      artifacts: {}
      steps:
        - id: build
    YAML
    cli(['task', 'create', '--workflow', 'quick', '--title', 't', '--root', root.to_s, '--json'], root)
  end

  def tamper_index(root)
    path = "#{root}/tasks/index.yaml"
    data = YAML.safe_load_file(path)
    yield data
    File.write(path, YAML.safe_dump(data))
  end

  it 'is empty when the index matches the task dirs' do
    with_tmp_project do |root|
      setup_project(root)
      result = Owl::Tasks::Api.index_drift(root: root)
      expect(result).to be_ok
      expect(result.value[:index_drift]).to be_empty
    end
  end

  it 'flags a task dir missing from the index' do
    with_tmp_project do |root|
      setup_project(root)
      tamper_index(root) { |d| d['tasks'] = [] }

      drift = Owl::Tasks::Api.index_drift(root: root).value[:index_drift]
      expect(drift).to contain_exactly(hash_including(task_id: 'TASK-0001', class: 'missing_from_index'))
    end
  end

  it 'flags a stale index entry whose task dir is gone' do
    with_tmp_project do |root|
      setup_project(root)
      tamper_index(root) do |d|
        d['tasks'] << { 'id' => 'TASK-0099', 'title' => 'ghost', 'status' => 'open' }
      end

      drift = Owl::Tasks::Api.index_drift(root: root).value[:index_drift]
      expect(drift).to include(hash_including(task_id: 'TASK-0099', class: 'stale_in_index'))
    end
  end

  it 'flags a per-field mismatch and names the fields' do
    with_tmp_project do |root|
      setup_project(root)
      tamper_index(root) do |d|
        d['tasks'].each { |t| t['status'] = 'blocked' if t['id'] == 'TASK-0001' }
      end

      drift = Owl::Tasks::Api.index_drift(root: root).value[:index_drift]
      expect(drift).to contain_exactly(
        hash_including(task_id: 'TASK-0001', class: 'field_mismatch', fields: ['status'])
      )
    end
  end

  it 'is reconciled by owl doctor --fix (rebuild_index)' do
    with_tmp_project do |root|
      setup_project(root)
      tamper_index(root) { |d| d['tasks'] = [] }

      Owl::Tasks::Api.rebuild_index(root: root)
      expect(Owl::Tasks::Api.index_drift(root: root).value[:index_drift]).to be_empty
    end
  end
end
