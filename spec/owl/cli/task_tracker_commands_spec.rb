# frozen_string_literal: true

require 'json'
require 'stringio'

require 'owl/cli/api'

RSpec.describe 'owl task tracker CLI subcommands' do
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
      kind: task
      artifacts: {}
      steps:
        - id: a
    YAML
  end

  def create_task(root, title: 't')
    run(['task', 'create', '--workflow', 'feature', '--title', title, '--root', root.to_s, '--json'], cwd: root)
  end

  describe 'owl task set-status' do
    it 'sets a valid status' do
      with_tmp_project do |root|
        setup_project(root)
        create_task(root)
        exit_code, stdout, = run(['task', 'set-status', 'TASK-0001', 'on_hold', '--root', root.to_s, '--json'],
                                 cwd: root)
        expect(exit_code).to eq(0)
        body = JSON.parse(stdout)
        expect(body['ok']).to be(true)
        expect(body['status']).to eq('on_hold')
      end
    end

    it 'reports invalid_status for a bad enum value' do
      with_tmp_project do |root|
        setup_project(root)
        create_task(root)
        exit_code, _stdout, stderr = run(['task', 'set-status', 'TASK-0001', 'bogus', '--root', root.to_s], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('invalid_status')
      end
    end

    it 'reports invalid_arguments when STATUS is missing' do
      with_tmp_project do |root|
        setup_project(root)
        exit_code, _stdout, stderr = run(['task', 'set-status', 'TASK-0001', '--root', root.to_s], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('invalid_arguments')
      end
    end

    it 'reports invalid_arguments for an unknown flag' do
      with_tmp_project do |root|
        setup_project(root)
        exit_code, _stdout, stderr = run(['task', 'set-status', '--bogus'], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('invalid_arguments')
      end
    end
  end

  describe 'owl task label' do
    it 'adds a label' do
      with_tmp_project do |root|
        setup_project(root)
        create_task(root)
        exit_code, stdout, = run(['task', 'label', 'add', 'TASK-0001', 'backend', '--root', root.to_s, '--json'],
                                 cwd: root)
        expect(exit_code).to eq(0)
        expect(JSON.parse(stdout)['labels']).to eq(['backend'])
      end
    end

    it 'removes a label' do
      with_tmp_project do |root|
        setup_project(root)
        create_task(root)
        run(['task', 'label', 'add', 'TASK-0001', 'backend', '--root', root.to_s, '--json'], cwd: root)
        exit_code, stdout, = run(['task', 'label', 'rm', 'TASK-0001', 'backend', '--root', root.to_s, '--json'],
                                 cwd: root)
        expect(exit_code).to eq(0)
        expect(JSON.parse(stdout)['labels']).to eq([])
      end
    end

    it 'reports invalid_arguments when LABEL is missing' do
      with_tmp_project do |root|
        setup_project(root)
        exit_code, _stdout, stderr = run(['task', 'label', 'add', 'TASK-0001', '--root', root.to_s], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('invalid_arguments')
      end
    end

    it 'reports invalid_arguments for an unknown flag' do
      with_tmp_project do |root|
        setup_project(root)
        exit_code, _stdout, stderr = run(['task', 'label', 'add', '--bogus'], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('invalid_arguments')
      end
    end

    it 'reports unknown_command for an unknown label subcommand' do
      with_tmp_project do |root|
        setup_project(root)
        exit_code, _stdout, stderr = run(['task', 'label', 'nope', 'TASK-0001', 'x', '--root', root.to_s], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('unknown_command')
      end
    end
  end

  describe 'owl task query' do
    def seed(root)
      setup_project(root)
      create_task(root, title: 'one')
      create_task(root, title: 'two')
      run(['task', 'set-status', 'TASK-0001', 'on_hold', '--root', root.to_s, '--json'], cwd: root)
      run(['task', 'label', 'add', 'TASK-0001', 'backend', '--root', root.to_s, '--json'], cwd: root)
    end

    it 'filters by combined status AND label' do
      with_tmp_project do |root|
        seed(root)
        exit_code, stdout, = run(
          ['task', 'query', '--status', 'on_hold', '--label', 'backend', '--root', root.to_s, '--json'],
          cwd: root
        )
        expect(exit_code).to eq(0)
        ids = JSON.parse(stdout)['tasks'].map { |t| t['id'] }
        expect(ids).to eq(['TASK-0001'])
      end
    end

    it 'returns the full roster with no filters' do
      with_tmp_project do |root|
        seed(root)
        _exit, stdout, = run(['task', 'query', '--root', root.to_s, '--json'], cwd: root)
        expect(JSON.parse(stdout)['tasks'].size).to eq(2)
      end
    end

    it 'reports invalid_arguments for a non-integer --priority' do
      with_tmp_project do |root|
        setup_project(root)
        exit_code, _stdout, stderr = run(['task', 'query', '--priority', 'high', '--root', root.to_s], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('invalid_arguments')
      end
    end
  end

  describe '--help lists the new subcommands' do
    it 'mentions set-status, label and query' do
      with_tmp_project do |root|
        _exit, _stdout, stderr = run(['--help'], cwd: root)
        expect(stderr).to include('task set-status')
        expect(stderr).to include('task label')
        expect(stderr).to include('task query')
      end
    end

    it 'lists them under the task group help' do
      with_tmp_project do |root|
        _exit, _stdout, stderr = run(['task'], cwd: root)
        expect(stderr).to include('set-status')
        expect(stderr).to include('label')
        expect(stderr).to include('query')
      end
    end
  end
end
