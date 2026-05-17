# frozen_string_literal: true

require 'json'
require 'pathname'
require 'stringio'
require 'yaml'

require 'owl/cli/api'
require 'owl/tasks/internal/atomic_yaml_writer'

RSpec.describe 'owl publish CLI' do
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
      artifacts:
        spec:
          type: spec
          storage:
            role: tasks
            path: "{{task.id}}/spec.md"
      publishes:
        - from: "{{task.id}}/spec.md"
          to: "{{task.id}}/spec.md"
      steps:
        - id: specify
          creates: [spec]
        - id: publish
          requires: [specify]
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

  it 'publishes the spec to docs and reports success as JSON' do
    with_tmp_project do |root|
      task_id = setup_project(root)
      write("#{root}/tasks/#{task_id}/spec.md", "# spec\n")
      force_step_done(root, task_id, 'specify')

      exit_code, stdout, = run(['publish', task_id, '--root', root.to_s, '--json'], cwd: root)
      expect(exit_code).to eq(0)
      body = JSON.parse(stdout)
      expect(body['ok']).to be(true)
      expect(body['task_id']).to eq(task_id)
      expect(body['dry_run']).to be(false)
      expect(body['results'].first['action']).to eq('created')
      expect(Pathname.new("#{root}/docs/#{task_id}/spec.md").read).to eq("# spec\n")
    end
  end

  it '--dry-run reports the plan and does not touch docs' do
    with_tmp_project do |root|
      task_id = setup_project(root)
      write("#{root}/tasks/#{task_id}/spec.md", "# spec\n")
      force_step_done(root, task_id, 'specify')

      exit_code, stdout, = run(['publish', task_id, '--dry-run', '--root', root.to_s, '--json'], cwd: root)
      expect(exit_code).to eq(0)
      body = JSON.parse(stdout)
      expect(body['dry_run']).to be(true)
      expect(body['results'].first['action']).to eq('created')
      expect(Pathname.new("#{root}/docs/#{task_id}/spec.md").exist?).to be(false)
    end
  end

  it 'returns no_publishable_step when publish step is missing' do
    with_tmp_project do |root|
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
        artifacts:
          spec:
            type: spec
            storage:
              role: tasks
              path: "{{task.id}}/spec.md"
        steps:
          - id: specify
            creates: [spec]
      YAML

      _, stdout_create, = run(['task', 'create', '--workflow', 'feature', '--title', 't',
                               '--root', root.to_s, '--json'], cwd: root)
      task_id = JSON.parse(stdout_create).dig('task', 'id')

      exit_code, _, stderr = run(['publish', task_id, '--root', root.to_s, '--json'], cwd: root)
      expect(exit_code).to eq(1)
      expect(JSON.parse(stderr).dig('error', 'code')).to eq('no_publishable_step')
    end
  end

  it 'requires the TASK-ID positional argument' do
    with_tmp_project do |root|
      run(['init', '--root', root.to_s], cwd: root)
      exit_code, _, stderr = run(['publish', '--root', root.to_s, '--json'], cwd: root)
      expect(exit_code).to eq(1)
      expect(JSON.parse(stderr).dig('error', 'code')).to eq('invalid_arguments')
    end
  end
end
