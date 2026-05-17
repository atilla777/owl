# frozen_string_literal: true

require 'json'
require 'stringio'

require 'owl/cli/api'

RSpec.describe 'owl task ... CLI subcommands' do
  def run(argv, cwd:)
    stdout = StringIO.new
    stderr = StringIO.new
    exit_code = Owl::Cli::Api.run(argv: argv, stdout: stdout, stderr: stderr, env: {}, cwd: cwd.to_s)
    [exit_code, stdout.string, stderr.string]
  end

  def init_project(root)
    run(['init', '--root', root.to_s], cwd: root)
  end

  def seed_feature_workflow(root)
    write("#{root}/.owl/workflows.yaml", <<~YAML)
      schema_version: 1
      workflows:
        feature:
          enabled: true
          source: "workflows/feature/workflow.yaml"
          version: "1.0"
    YAML
    write("#{root}/.owl/workflows/feature/workflow.yaml", <<~YAML)
      id: feature
      kind: feature
      steps:
        - id: noop
          kind: noop
      artifacts: []
    YAML
  end

  describe '--help' do
    it 'mentions the task subcommand block' do
      with_tmp_project do |root|
        _exit, _stdout, stderr = run(['--help'], cwd: root)
        expect(stderr).to include('task create')
        expect(stderr).to include('task list')
        expect(stderr).to include('task index rebuild')
      end
    end
  end

  describe 'owl task create' do
    it 'creates a TASK-0001 with happy path arguments' do
      with_tmp_project do |root|
        init_project(root)
        seed_feature_workflow(root)
        exit_code, stdout, _stderr = run(
          ['task', 'create', '--workflow', 'feature', '--title', 'first',
           '--root', root.to_s, '--json'],
          cwd: root
        )
        expect(exit_code).to eq(0)
        body = JSON.parse(stdout)
        expect(body['ok']).to be(true)
        expect(body.dig('task', 'id')).to eq('TASK-0001')
        expect(body.dig('task', 'workflow', 'key')).to eq('feature')
      end
    end

    it 'reports invalid_arguments when --workflow is missing' do
      with_tmp_project do |root|
        init_project(root)
        exit_code, _stdout, stderr = run(
          ['task', 'create', '--title', 'x', '--root', root.to_s],
          cwd: root
        )
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('invalid_arguments')
      end
    end

    it 'reports unknown_workflow when the workflow is not registered' do
      with_tmp_project do |root|
        init_project(root)
        exit_code, _stdout, stderr = run(
          ['task', 'create', '--workflow', 'nope', '--title', 'x', '--root', root.to_s],
          cwd: root
        )
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('unknown_workflow')
      end
    end

    it 'reports invalid_arguments for an unknown flag' do
      with_tmp_project do |root|
        init_project(root)
        exit_code, _stdout, stderr = run(['task', 'create', '--bogus'], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('invalid_arguments')
      end
    end

    it 'reports project_root_not_found when no .owl/ is present' do
      with_tmp_project do |root|
        exit_code, _stdout, stderr = run(
          ['task', 'create', '--workflow', 'feature', '--title', 'x'],
          cwd: root
        )
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('project_root_not_found')
      end
    end
  end

  describe 'owl task list' do
    it 'returns an empty tasks array on a fresh project' do
      with_tmp_project do |root|
        init_project(root)
        exit_code, stdout, _stderr = run(['task', 'list', '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).to eq(0)
        expect(JSON.parse(stdout)['tasks']).to eq([])
      end
    end

    it 'returns previously created tasks' do
      with_tmp_project do |root|
        init_project(root)
        seed_feature_workflow(root)
        run(['task', 'create', '--workflow', 'feature', '--title', 'a', '--root', root.to_s], cwd: root)
        run(['task', 'create', '--workflow', 'feature', '--title', 'b', '--root', root.to_s], cwd: root)
        _exit, stdout, _stderr = run(['task', 'list', '--root', root.to_s, '--json'], cwd: root)
        ids = JSON.parse(stdout)['tasks'].map { |t| t['id'] }
        expect(ids).to eq(%w[TASK-0001 TASK-0002])
      end
    end
  end

  describe 'owl task inspect' do
    it 'returns the task payload' do
      with_tmp_project do |root|
        init_project(root)
        seed_feature_workflow(root)
        run(['task', 'create', '--workflow', 'feature', '--title', 'a', '--root', root.to_s], cwd: root)
        exit_code, stdout, _stderr = run(['task', 'inspect', 'TASK-0001', '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).to eq(0)
        expect(JSON.parse(stdout).dig('task', 'title')).to eq('a')
      end
    end

    it 'reports task_not_found when missing' do
      with_tmp_project do |root|
        init_project(root)
        exit_code, _stdout, stderr = run(['task', 'inspect', 'TASK-9999', '--root', root.to_s], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('task_not_found')
      end
    end

    it 'reports invalid_arguments when no TASK-ID is provided' do
      with_tmp_project do |root|
        init_project(root)
        exit_code, _stdout, stderr = run(['task', 'inspect', '--root', root.to_s], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('invalid_arguments')
      end
    end
  end

  describe 'owl task use + current' do
    it 'sets and reads back the current pointer' do
      with_tmp_project do |root|
        init_project(root)
        seed_feature_workflow(root)
        run(['task', 'create', '--workflow', 'feature', '--title', 'a', '--root', root.to_s], cwd: root)

        use_exit, use_stdout, _stderr = run(['task', 'use', 'TASK-0001', '--root', root.to_s, '--json'], cwd: root)
        expect(use_exit).to eq(0)
        expect(JSON.parse(use_stdout)['task_id']).to eq('TASK-0001')

        cur_exit, cur_stdout, _stderr = run(['task', 'current', '--root', root.to_s, '--json'], cwd: root)
        expect(cur_exit).to eq(0)
        expect(JSON.parse(cur_stdout)['task_id']).to eq('TASK-0001')
      end
    end

    it 'use reports invalid_arguments when no TASK-ID is provided' do
      with_tmp_project do |root|
        init_project(root)
        exit_code, _stdout, stderr = run(['task', 'use', '--root', root.to_s], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('invalid_arguments')
      end
    end

    it 'current reports no_current_task when no pointer is set' do
      with_tmp_project do |root|
        init_project(root)
        exit_code, _stdout, stderr = run(['task', 'current', '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('no_current_task')
      end
    end
  end

  describe 'owl task index rebuild' do
    it 'rebuilds the index after manual edits' do
      with_tmp_project do |root|
        init_project(root)
        seed_feature_workflow(root)
        run(['task', 'create', '--workflow', 'feature', '--title', 'a', '--root', root.to_s], cwd: root)

        path = Pathname.new("#{root}/tasks/TASK-0001/task.yaml")
        edited = YAML.safe_load(path.read)
        edited['title'] = 'edited'
        path.write(YAML.dump(edited))

        exit_code, stdout, _stderr = run(['task', 'index', 'rebuild', '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).to eq(0)
        body = JSON.parse(stdout)
        expect(body['tasks'].first['title']).to eq('edited')
      end
    end
  end

  describe 'unknown task subcommand' do
    it 'reports unknown_command for a typo' do
      with_tmp_project do |root|
        init_project(root)
        exit_code, _stdout, stderr = run(['task', 'nope', '--root', root.to_s], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('unknown_command')
      end
    end

    it 'reports unknown_command for a typo under task index' do
      with_tmp_project do |root|
        init_project(root)
        exit_code, _stdout, stderr = run(['task', 'index', 'nope', '--root', root.to_s], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('unknown_command')
      end
    end
  end
end
