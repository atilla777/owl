# frozen_string_literal: true

require 'json'
require 'stringio'
require 'yaml'

require 'owl/cli/api'
require 'owl/steps/api'

RSpec.describe Owl::Steps::Api do
  def cli(argv, root)
    stdout = StringIO.new
    stderr = StringIO.new
    Owl::Cli::Api.run(argv: argv, stdout: stdout, stderr: stderr, env: {}, cwd: root.to_s)
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
      kind: feature
      steps:
        - id: a
        - id: b
          requires: ["a"]
      artifacts: []
    YAML
    cli(['task', 'create', '--workflow', 'feature', '--title', 't', '--root', root.to_s, '--json'], root)
    'TASK-0001'
  end

  def task_yaml(root, task_id = 'TASK-0001')
    YAML.safe_load_file("#{root}/tasks/#{task_id}/task.yaml")
  end

  describe '.start' do
    it 'moves a ready step to running' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        result = described_class.start(root: root, task_id: task_id, step_id: 'a')
        expect(result).to be_ok

        step = task_yaml(root)['steps'].find { |s| s['id'] == 'a' }
        expect(step['status']).to eq('running')
      end
    end

    it 'refuses to start a non-ready step' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        result = described_class.start(root: root, task_id: task_id, step_id: 'b')
        expect(result).to be_err
        expect(result.code).to eq(:step_not_ready)
        expect(result.details[:ready_steps]).to eq(['a'])
      end
    end

    it 'refuses to start an already-running step' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        described_class.start(root: root, task_id: task_id, step_id: 'a')
        result = described_class.start(root: root, task_id: task_id, step_id: 'a')
        expect(result).to be_err
        expect(result.code).to eq(:step_not_ready)
      end
    end
  end

  describe '.complete' do
    it 'moves a running step to done' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        described_class.start(root: root, task_id: task_id, step_id: 'a')
        result = described_class.complete(root: root, task_id: task_id, step_id: 'a')
        expect(result).to be_ok

        step = task_yaml(root)['steps'].find { |s| s['id'] == 'a' }
        expect(step['status']).to eq('done')
      end
    end

    it 'refuses to complete a pending step' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        result = described_class.complete(root: root, task_id: task_id, step_id: 'a')
        expect(result).to be_err
        expect(result.code).to eq(:step_not_running)
      end
    end

    it 'refuses to complete a done step' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        described_class.start(root: root, task_id: task_id, step_id: 'a')
        described_class.complete(root: root, task_id: task_id, step_id: 'a')
        result = described_class.complete(root: root, task_id: task_id, step_id: 'a')
        expect(result).to be_err
        expect(result.code).to eq(:step_not_running)
      end
    end

    it 'reports unknown_step_id for an undefined step' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        result = described_class.complete(root: root, task_id: task_id, step_id: 'ghost')
        expect(result).to be_err
        expect(result.code).to eq(:unknown_step_id)
      end
    end
  end

  describe '.skip' do
    it 'writes status skipped and a skip_reason' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        result = described_class.skip(root: root, task_id: task_id, step_id: 'a', reason: 'not applicable')
        expect(result).to be_ok

        step = task_yaml(root)['steps'].find { |s| s['id'] == 'a' }
        expect(step['status']).to eq('skipped')
        expect(step['skip_reason']).to eq('not applicable')
      end
    end

    it 'unblocks downstream after skip' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        described_class.skip(root: root, task_id: task_id, step_id: 'a', reason: 'no-op')
        ready = Owl::Workflows::Api.ready_steps(root: root, task_id: task_id).value[:ready]
        expect(ready.map { |s| s[:id] }).to eq(['b'])
      end
    end

    it 'rejects empty reason' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        result = described_class.skip(root: root, task_id: task_id, step_id: 'a', reason: '   ')
        expect(result).to be_err
        expect(result.code).to eq(:missing_reason)
      end
    end

    it 'rejects skipping a done step' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        described_class.start(root: root, task_id: task_id, step_id: 'a')
        described_class.complete(root: root, task_id: task_id, step_id: 'a')
        result = described_class.skip(root: root, task_id: task_id, step_id: 'a', reason: 'late')
        expect(result).to be_err
        expect(result.code).to eq(:step_already_done)
      end
    end

    it 'reports unknown_step_id for an undefined step' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        result = described_class.skip(root: root, task_id: task_id, step_id: 'ghost', reason: 'x')
        expect(result).to be_err
        expect(result.code).to eq(:unknown_step_id)
      end
    end
  end
end
