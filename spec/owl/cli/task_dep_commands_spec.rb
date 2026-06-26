# frozen_string_literal: true

require 'json'
require 'stringio'

require 'owl/cli/api'

RSpec.describe 'owl task dep / ready CLI subcommands' do
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

  def create_two(root)
    setup_project(root)
    create_task(root, title: 'A')
    create_task(root, title: 'B')
  end

  describe 'owl task dep add' do
    it 'adds a dependency edge' do
      with_tmp_project do |root|
        create_two(root)
        exit_code, stdout, = run(
          ['task', 'dep', 'add', 'TASK-0002', '--on', 'TASK-0001', '--root', root.to_s, '--json'], cwd: root
        )
        expect(exit_code).to eq(0)
        body = JSON.parse(stdout)
        expect(body['ok']).to be(true)
        expect(body['blocked_by']).to eq(['TASK-0001'])
      end
    end

    it 'reports self_dependency' do
      with_tmp_project do |root|
        create_two(root)
        exit_code, _stdout, stderr = run(
          ['task', 'dep', 'add', 'TASK-0001', '--on', 'TASK-0001', '--root', root.to_s], cwd: root
        )
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('self_dependency')
      end
    end

    it 'reports dependency_cycle' do
      with_tmp_project do |root|
        create_two(root)
        run(['task', 'dep', 'add', 'TASK-0002', '--on', 'TASK-0001', '--root', root.to_s], cwd: root)
        exit_code, _stdout, stderr = run(
          ['task', 'dep', 'add', 'TASK-0001', '--on', 'TASK-0002', '--root', root.to_s], cwd: root
        )
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('dependency_cycle')
      end
    end

    it 'reports invalid_arguments when --on is missing' do
      with_tmp_project do |root|
        create_two(root)
        exit_code, _stdout, stderr = run(['task', 'dep', 'add', 'TASK-0002', '--root', root.to_s], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('invalid_arguments')
      end
    end

    it 'reports invalid_arguments for an unknown flag' do
      with_tmp_project do |root|
        create_two(root)
        exit_code, _stdout, stderr = run(['task', 'dep', 'add', '--bogus'], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('invalid_arguments')
      end
    end
  end

  describe 'owl task dep rm' do
    it 'removes a dependency edge' do
      with_tmp_project do |root|
        create_two(root)
        run(['task', 'dep', 'add', 'TASK-0002', '--on', 'TASK-0001', '--root', root.to_s], cwd: root)
        exit_code, stdout, = run(
          ['task', 'dep', 'rm', 'TASK-0002', '--on', 'TASK-0001', '--root', root.to_s, '--json'], cwd: root
        )
        expect(exit_code).to eq(0)
        expect(JSON.parse(stdout)['blocked_by']).to eq([])
      end
    end
  end

  describe 'owl task dep list' do
    it 'lists blocked_by and computed blocks' do
      with_tmp_project do |root|
        create_two(root)
        run(['task', 'dep', 'add', 'TASK-0002', '--on', 'TASK-0001', '--root', root.to_s], cwd: root)
        exit_code, stdout, = run(['task', 'dep', 'list', 'TASK-0001', '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).to eq(0)
        body = JSON.parse(stdout)
        expect(body['blocked_by']).to eq([])
        expect(body['blocks']).to eq(['TASK-0002'])
      end
    end

    it 'reports invalid_arguments when TASK-ID is missing' do
      with_tmp_project do |root|
        create_two(root)
        exit_code, _stdout, stderr = run(['task', 'dep', 'list', '--root', root.to_s], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('invalid_arguments')
      end
    end
  end

  describe 'owl task dep (unknown subcommand)' do
    it 'reports unknown_command' do
      with_tmp_project do |root|
        create_two(root)
        exit_code, _stdout, stderr = run(['task', 'dep', 'bogus', '--root', root.to_s], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('unknown_command')
      end
    end
  end

  describe 'owl task ready' do
    it 'lists dependency-ready tasks, excluding blocked ones' do
      with_tmp_project do |root|
        create_two(root)
        run(['task', 'dep', 'add', 'TASK-0002', '--on', 'TASK-0001', '--root', root.to_s], cwd: root)
        exit_code, stdout, = run(['task', 'ready', '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).to eq(0)
        ready = JSON.parse(stdout)['ready']
        ids = ready.map { |e| e['task_id'] }
        expect(ids).to include('TASK-0001')
        expect(ids).not_to include('TASK-0002')
        expect(ready.first).not_to have_key('id')
      end
    end

    it 'reports invalid_arguments for an unknown flag' do
      with_tmp_project do |root|
        create_two(root)
        exit_code, _stdout, stderr = run(['task', 'ready', '--bogus'], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('invalid_arguments')
      end
    end
  end
end
