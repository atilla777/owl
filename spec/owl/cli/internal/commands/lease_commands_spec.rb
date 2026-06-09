# frozen_string_literal: true

require 'json'
require 'stringio'

require 'owl/cli/api'

RSpec.describe 'owl task/step lease CLI subcommands' do
  def cli(argv, root)
    stdout = StringIO.new
    stderr = StringIO.new
    code = Owl::Cli::Api.run(argv: argv, stdout: stdout, stderr: stderr, env: {}, cwd: root.to_s)
    [code, stdout.string, stderr.string]
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
  end

  def create(root, title, priority = nil)
    argv = ['task', 'create', '--workflow', 'feature', '--title', title, '--root', root.to_s, '--json']
    argv += ['--priority', priority.to_s] if priority
    cli(argv, root)
  end

  describe 'task claim' do
    it 'claims a task and emits the token + ready steps' do
      with_tmp_project do |root|
        setup_project(root)
        create(root, 't')
        code, out, = cli(['task', 'claim', 'TASK-0001', '--root', root.to_s, '--json'], root)
        expect(code).to eq(0)
        body = JSON.parse(out)
        expect(body['ok']).to be(true)
        expect(body['task_id']).to eq('TASK-0001')
        expect(body['token']).to be_a(String)
        expect(body['ready_step_ids']).to eq(['a'])
      end
    end

    it 'auto-selects with --next' do
      with_tmp_project do |root|
        setup_project(root)
        create(root, 'low')
        create(root, 'high', 9)
        _code, out, = cli(['task', 'claim', '--next', '--root', root.to_s, '--json'], root)
        expect(JSON.parse(out)['task_id']).to eq('TASK-0002')
      end
    end

    it 'fails (exit 1) when claiming an already-claimed task' do
      with_tmp_project do |root|
        setup_project(root)
        create(root, 't')
        cli(['task', 'claim', 'TASK-0001', '--root', root.to_s, '--json'], root)
        code, _out, err = cli(['task', 'claim', 'TASK-0001', '--root', root.to_s, '--json'], root)
        expect(code).to eq(1)
        expect(JSON.parse(err)['error']['code']).to eq('lease_held')
      end
    end
  end

  describe 'task release' do
    it 'releases a held claim' do
      with_tmp_project do |root|
        setup_project(root)
        create(root, 't')
        _c, claim_out, = cli(['task', 'claim', 'TASK-0001', '--root', root.to_s, '--json'], root)
        token = JSON.parse(claim_out)['token']
        code, out, = cli(['task', 'release', 'TASK-0001', '--token', token, '--root', root.to_s, '--json'], root)
        expect(code).to eq(0)
        expect(JSON.parse(out)['released']).to be(true)
      end
    end

    it 'rejects a release without --token' do
      with_tmp_project do |root|
        setup_project(root)
        create(root, 't')
        code, _out, err = cli(['task', 'release', 'TASK-0001', '--root', root.to_s, '--json'], root)
        expect(code).to eq(1)
        expect(JSON.parse(err)['error']['code']).to eq('invalid_arguments')
      end
    end
  end

  describe 'task claims' do
    it 'lists active claims' do
      with_tmp_project do |root|
        setup_project(root)
        create(root, 't')
        cli(['task', 'claim', 'TASK-0001', '--root', root.to_s, '--json'], root)
        _code, out, = cli(['task', 'claims', '--root', root.to_s, '--json'], root)
        expect(JSON.parse(out)['claims'].first['task_id']).to eq('TASK-0001')
      end
    end
  end

  describe 'task available' do
    it 'lists runnable tasks ranked by priority' do
      with_tmp_project do |root|
        setup_project(root)
        create(root, 'low')
        create(root, 'high', 5)
        _code, out, = cli(['task', 'available', '--root', root.to_s, '--json'], root)
        ids = JSON.parse(out)['available'].map { |c| c['task_id'] }
        expect(ids).to eq(%w[TASK-0002 TASK-0001])
      end
    end
  end

  describe 'task set-priority' do
    it 'sets an integer priority' do
      with_tmp_project do |root|
        setup_project(root)
        create(root, 't')
        code, out, = cli(['task', 'set-priority', 'TASK-0001', '8', '--root', root.to_s, '--json'], root)
        expect(code).to eq(0)
        expect(JSON.parse(out)['priority']).to eq(8)
      end
    end

    it 'rejects missing positional arguments' do
      with_tmp_project do |root|
        setup_project(root)
        create(root, 't')
        code, _out, err = cli(['task', 'set-priority', 'TASK-0001', '--root', root.to_s, '--json'], root)
        expect(code).to eq(1)
        expect(JSON.parse(err)['error']['code']).to eq('invalid_arguments')
      end
    end
  end

  describe 'task adopt' do
    it 'adopts a task and resets running steps' do
      with_tmp_project do |root|
        setup_project(root)
        create(root, 't')
        cli(['step', 'start', 'TASK-0001', 'a', '--root', root.to_s, '--json'], root)
        code, out, = cli(['task', 'adopt', 'TASK-0001', '--root', root.to_s, '--json'], root)
        expect(code).to eq(0)
        body = JSON.parse(out)
        expect(body['reopened']).to eq(['a'])
        expect(body['token']).to be_a(String)
      end
    end

    it 'requires a TASK-ID' do
      with_tmp_project do |root|
        setup_project(root)
        code, _out, err = cli(['task', 'adopt', '--root', root.to_s, '--json'], root)
        expect(code).to eq(1)
        expect(JSON.parse(err)['error']['code']).to eq('invalid_arguments')
      end
    end
  end

  describe 'step reset' do
    it 'resets a running step to pending' do
      with_tmp_project do |root|
        setup_project(root)
        create(root, 't')
        cli(['step', 'start', 'TASK-0001', 'a', '--root', root.to_s, '--json'], root)
        code, out, = cli(['step', 'reset', 'TASK-0001', 'a', '--root', root.to_s, '--json'], root)
        expect(code).to eq(0)
        expect(JSON.parse(out)['step']['status']).to eq('pending')
      end
    end
  end
end
