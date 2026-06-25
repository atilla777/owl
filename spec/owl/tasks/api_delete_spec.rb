# frozen_string_literal: true

require 'json'
require 'stringio'
require 'yaml'

require 'owl/cli/api'
require 'owl/tasks/api'
require 'owl/tasks/internal/deleter'
require 'owl/locks/api'

RSpec.describe Owl::Tasks::Api, '.delete' do
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

  def index_tasks(root)
    YAML.safe_load_file("#{root}/tasks/index.yaml")['tasks']
  end

  it 'physically removes the task directory' do
    with_tmp_project do |root|
      task_id = setup_project(root)
      result = described_class.delete(root: root, task_id: task_id)
      expect(result).to be_ok
      expect(result.value[:removed]).to be(true)
      expect(Pathname.new("#{root}/tasks/#{task_id}").exist?).to be(false)
    end
  end

  it 'rebuilds index so the task no longer appears in tasks/index.yaml' do
    with_tmp_project do |root|
      task_id = setup_project(root)
      described_class.delete(root: root, task_id: task_id)
      expect(index_tasks(root).map { |t| t['id'] }).not_to include(task_id)
    end
  end

  it 'deletes an abandoned task' do
    with_tmp_project do |root|
      task_id = setup_project(root)
      described_class.abandon(root: root, task_id: task_id)
      result = described_class.delete(root: root, task_id: task_id)
      expect(result).to be_ok
      expect(Pathname.new("#{root}/tasks/#{task_id}").exist?).to be(false)
    end
  end

  it 'returns task_not_found for an unknown task' do
    with_tmp_project do |root|
      setup_project(root)
      result = described_class.delete(root: root, task_id: 'TASK-9999')
      expect(result).to be_err
      expect(result.code).to eq(:task_not_found)
    end
  end

  it 'holds the deleted task lock for rm_rf and surfaces lock_held without removing the dir' do
    with_tmp_project do |root|
      task_id = setup_project(root)
      # A foreign session holds the deleted task's mutation lock and never
      # releases it; with the clock already past the acquire deadline, delete
      # gives up with a recoverable lock_held and must NOT remove the directory.
      Owl::Locks::Api.acquire(root: root, name: "task-#{task_id}", token: 'foreign')
      clock = class_double(Time)
      now = Time.now
      allow(clock).to receive(:now)
        .and_return(now, now + Owl::Tasks::Internal::TaskMutationLock::ACQUIRE_TIMEOUT_SECONDS + 1)

      result = Owl::Tasks::Internal::Deleter.call(
        root: root, task_id: task_id, clock: clock, sleeper: ->(_s) {}
      )

      expect(result).to be_err
      expect(result.code).to eq(:lock_held)
      expect(Pathname.new("#{root}/tasks/#{task_id}").exist?).to be(true)
    end
  end
end
