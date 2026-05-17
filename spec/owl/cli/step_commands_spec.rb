# frozen_string_literal: true

require 'json'
require 'stringio'
require 'yaml'

require 'owl/cli/api'

RSpec.describe 'owl step ... and owl task ready-steps CLI subcommands' do
  def run(argv, cwd:)
    stdout = StringIO.new
    stderr = StringIO.new
    exit_code = Owl::Cli::Api.run(argv: argv, stdout: stdout, stderr: stderr, env: {}, cwd: cwd.to_s)
    [exit_code, stdout.string, stderr.string]
  end

  def setup_project(root)
    run(['init', '--root', root.to_s], cwd: root)
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
    run(['task', 'create', '--workflow', 'feature', '--title', 't', '--root', root.to_s], cwd: root)
    'TASK-0001'
  end

  describe 'task ready-steps' do
    it 'prints the ready set as JSON' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        exit_code, stdout, _stderr = run(['task', 'ready-steps', task_id, '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).to eq(0)
        body = JSON.parse(stdout)
        expect(body['ok']).to be(true)
        expect(body['ready'].map { |s| s['id'] }).to eq(['a'])
      end
    end

    it 'fails with invalid_arguments when TASK-ID is missing' do
      with_tmp_project do |root|
        setup_project(root)
        exit_code, _stdout, stderr = run(['task', 'ready-steps', '--root', root.to_s], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('invalid_arguments')
      end
    end

    it 'fails with task_not_found when the task does not exist' do
      with_tmp_project do |root|
        setup_project(root)
        exit_code, _stdout, stderr = run(['task', 'ready-steps', 'TASK-9999', '--root', root.to_s], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('task_not_found')
      end
    end
  end

  describe 'step start / complete / skip' do
    it 'walks a linear workflow start → complete → next ready' do
      with_tmp_project do |root|
        task_id = setup_project(root)

        start_exit, start_stdout, = run(['step', 'start', task_id, 'a', '--root', root.to_s, '--json'], cwd: root)
        expect(start_exit).to eq(0)
        expect(JSON.parse(start_stdout).dig('step', 'status')).to eq('running')

        complete_args = ['step', 'complete', task_id, 'a', '--root', root.to_s, '--json']
        complete_exit, complete_stdout, = run(complete_args, cwd: root)
        expect(complete_exit).to eq(0)
        expect(JSON.parse(complete_stdout).dig('step', 'status')).to eq('done')

        _ready_exit, ready_stdout, = run(['task', 'ready-steps', task_id, '--root', root.to_s, '--json'], cwd: root)
        expect(JSON.parse(ready_stdout)['ready'].map { |s| s['id'] }).to eq(['b'])
      end
    end

    it 'returns step_not_ready exit 1 with structured error' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        exit_code, _stdout, stderr = run(['step', 'start', task_id, 'b', '--root', root.to_s], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('step_not_ready')
      end
    end

    it 'returns step_not_running for complete on a pending step' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        exit_code, _stdout, stderr = run(['step', 'complete', task_id, 'a', '--root', root.to_s], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('step_not_running')
      end
    end

    it 'records skip_reason and returns ok' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        skip_args = ['step', 'skip', task_id, 'a', '--reason', 'unused', '--root', root.to_s, '--json']
        exit_code, stdout, = run(skip_args, cwd: root)
        expect(exit_code).to eq(0)
        body = JSON.parse(stdout)
        expect(body.dig('step', 'status')).to eq('skipped')
        expect(body.dig('step', 'skip_reason')).to eq('unused')
      end
    end

    it 'returns missing_reason when --reason is omitted' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        exit_code, _stdout, stderr = run(['step', 'skip', task_id, 'a', '--root', root.to_s], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('missing_reason')
      end
    end

    it 'returns invalid_arguments when STEP-ID is missing' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        exit_code, _stdout, stderr = run(['step', 'start', task_id, '--root', root.to_s], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('invalid_arguments')
      end
    end
  end

  describe 'unknown step subcommand' do
    it 'reports unknown_command' do
      with_tmp_project do |root|
        setup_project(root)
        exit_code, _stdout, stderr = run(['step', 'nope', '--root', root.to_s], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('unknown_command')
      end
    end

    it 'reports unknown_command for bare step' do
      with_tmp_project do |root|
        setup_project(root)
        exit_code, _stdout, stderr = run(['step', '--root', root.to_s], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('unknown_command')
      end
    end
  end
end
