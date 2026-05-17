# frozen_string_literal: true

require 'json'
require 'pathname'
require 'stringio'
require 'yaml'

require 'owl/cli/api'
require 'owl/tasks/internal/atomic_yaml_writer'

RSpec.describe 'owl archive CLI' do
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
      steps:
        - id: specify
        - id: verify
          requires: [specify]
        - id: publish
          requires: [verify]
    YAML

    _, stdout, = run(['task', 'create', '--workflow', 'feature', '--title', 't',
                      '--root', root.to_s, '--json'], cwd: root)
    JSON.parse(stdout).dig('task', 'id')
  end

  def force_step_done(root, task_id, step_id)
    task_path = Pathname.new(root) + 'tasks' + task_id + 'task.yaml'
    payload = YAML.safe_load(task_path.read, aliases: false, permitted_classes: [Time])
    payload['steps'].find { |s| s['id'] == step_id }['status'] = 'done'
    Owl::Tasks::Internal::AtomicYamlWriter.write(path: task_path, payload: payload)
  end

  it 'archives the task and reports JSON success' do
    with_tmp_project do |root|
      task_id = setup_project(root)
      %w[specify verify publish].each { |s| force_step_done(root, task_id, s) }

      exit_code, stdout, = run(['archive', task_id, '--root', root.to_s, '--json'], cwd: root)
      expect(exit_code).to eq(0)
      body = JSON.parse(stdout)
      expect(body['ok']).to be(true)
      expect(body['task_id']).to eq(task_id)
      expect(body['to']).to include('tasks/archive/')
      expect(body['archived_at']).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/)
      expect(Pathname.new("#{root}/tasks/#{task_id}").exist?).to be(false)
    end
  end

  it 'requires the TASK-ID positional argument' do
    with_tmp_project do |root|
      run(['init', '--root', root.to_s], cwd: root)
      exit_code, _, stderr = run(['archive', '--root', root.to_s, '--json'], cwd: root)
      expect(exit_code).to eq(1)
      expect(JSON.parse(stderr).dig('error', 'code')).to eq('invalid_arguments')
    end
  end

  it 'returns workflow_incomplete when steps are not done' do
    with_tmp_project do |root|
      task_id = setup_project(root)
      # leave all steps as pending
      exit_code, _, stderr = run(['archive', task_id, '--root', root.to_s, '--json'], cwd: root)
      expect(exit_code).to eq(1)
      body = JSON.parse(stderr)
      expect(body.dig('error', 'code')).to eq('workflow_incomplete')
      ids = body.dig('error', 'details', 'incomplete_steps').map { |s| s['id'] }
      expect(ids).to eq(%w[specify verify publish])
    end
  end
end
