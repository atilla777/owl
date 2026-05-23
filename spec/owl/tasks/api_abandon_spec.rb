# frozen_string_literal: true

require 'json'
require 'stringio'
require 'yaml'

require 'owl/cli/api'
require 'owl/tasks/api'

RSpec.describe Owl::Tasks::Api, '.abandon' do
  def cli(argv, root)
    Owl::Cli::Api.run(argv: argv, stdout: StringIO.new, stderr: StringIO.new, env: {}, cwd: root.to_s)
  end

  def setup_project(root)
    cli(['init', '--root', root.to_s], root)
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
      artifacts: {}
      steps:
        - id: a
    YAML
    cli(['task', 'create', '--workflow', 'feature', '--title', 't', '--root', root.to_s, '--json'], root)
    'TASK-0001'
  end

  def task_yaml(root, task_id = 'TASK-0001')
    YAML.safe_load_file("#{root}/tasks/#{task_id}/task.yaml")
  end

  def index_yaml(root)
    YAML.safe_load_file("#{root}/tasks/index.yaml")
  end

  it 'writes status=abandoned and abandoned_at to task.yaml' do
    with_tmp_project do |root|
      task_id = setup_project(root)
      result = described_class.abandon(root: root, task_id: task_id, now: Time.utc(2026, 5, 23, 12, 0, 0))
      expect(result).to be_ok

      payload = task_yaml(root, task_id)
      expect(payload['status']).to eq('abandoned')
      expect(payload['abandoned_at']).to eq('2026-05-23T12:00:00Z')
      expect(payload).not_to have_key('abandon_reason')
    end
  end

  it 'stores --reason in task.yaml when provided' do
    with_tmp_project do |root|
      task_id = setup_project(root)
      described_class.abandon(root: root, task_id: task_id, reason: 'no longer needed')
      expect(task_yaml(root, task_id)['abandon_reason']).to eq('no longer needed')
    end
  end

  it 'rebuilds index.yaml so the abandoned status appears in the index entry' do
    with_tmp_project do |root|
      task_id = setup_project(root)
      described_class.abandon(root: root, task_id: task_id)

      entry = index_yaml(root)['tasks'].find { |t| t['id'] == task_id }
      expect(entry['status']).to eq('abandoned')
    end
  end

  it 'is idempotent when reason is omitted on already-abandoned tasks' do
    with_tmp_project do |root|
      task_id = setup_project(root)
      first = described_class.abandon(root: root, task_id: task_id, now: Time.utc(2026, 5, 23))
      original_ts = first.value[:abandoned_at]

      second = described_class.abandon(root: root, task_id: task_id, now: Time.utc(2026, 6, 1))
      expect(second).to be_ok
      expect(second.value[:abandoned_at]).to eq(original_ts)
      expect(second.value[:idempotent]).to be(true)
    end
  end

  it 'overrides status: archived when an archived task is abandoned' do
    with_tmp_project do |root|
      task_id = setup_project(root)
      payload = task_yaml(root, task_id)
      payload['status'] = 'archived'
      payload['archived_at'] = '2026-05-01T00:00:00Z'
      File.write("#{root}/tasks/#{task_id}/task.yaml", YAML.dump(payload))

      described_class.abandon(root: root, task_id: task_id)
      updated = task_yaml(root, task_id)
      expect(updated['status']).to eq('abandoned')
      expect(updated['archived_at']).to eq('2026-05-01T00:00:00Z')
    end
  end

  it 'returns task_not_found for an unknown task' do
    with_tmp_project do |root|
      setup_project(root)
      result = described_class.abandon(root: root, task_id: 'TASK-9999')
      expect(result).to be_err
      expect(result.code).to eq(:task_not_found)
    end
  end
end
