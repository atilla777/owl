# frozen_string_literal: true

require 'json'
require 'pathname'
require 'stringio'
require 'yaml'

require 'owl/cli/api'
require 'owl/tasks/internal/atomic_yaml_writer'

RSpec.describe 'owl archive read-only CLI' do
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

  def archive_a_task(root)
    task_id = setup_project(root)
    write("#{root}/tasks/#{task_id}/review.md", "# review body\nfindings here\n")
    %w[specify verify publish].each { |s| force_step_done(root, task_id, s) }
    run(['archive', task_id, '--root', root.to_s, '--json'], cwd: root)
    task_id
  end

  it 'routes `archive list` to the read-only list command' do
    with_tmp_project do |root|
      task_id = archive_a_task(root)
      exit_code, stdout, = run(['archive', 'list', '--root', root.to_s, '--json'], cwd: root)
      expect(exit_code).to eq(0)
      body = JSON.parse(stdout)
      expect(body['ok']).to be(true)
      expect(body['archived'].map { |e| e['task_id'] }).to eq([task_id])
    end
  end

  it 'returns an empty list (not an error) when nothing is archived' do
    with_tmp_project do |root|
      setup_project(root)
      exit_code, stdout, = run(['archive', 'list', '--root', root.to_s, '--json'], cwd: root)
      expect(exit_code).to eq(0)
      expect(JSON.parse(stdout)).to eq('ok' => true, 'archived' => [])
    end
  end

  it 'routes `archive show` and reports the artifact inventory' do
    with_tmp_project do |root|
      task_id = archive_a_task(root)
      exit_code, stdout, = run(['archive', 'show', task_id, '--root', root.to_s, '--json'], cwd: root)
      expect(exit_code).to eq(0)
      body = JSON.parse(stdout)
      expect(body['task_id']).to eq(task_id)
      expect(body['artifacts'].map { |a| a['key'] }).to include('review')
    end
  end

  it 'returns archived_task_not_found with available_ids for an unknown show id' do
    with_tmp_project do |root|
      archive_a_task(root)
      exit_code, _, stderr = run(['archive', 'show', 'TASK-9999', '--root', root.to_s, '--json'], cwd: root)
      expect(exit_code).to eq(1)
      err = JSON.parse(stderr)['error']
      expect(err['code']).to eq('archived_task_not_found')
      expect(err.dig('details', 'available_ids')).to eq(['TASK-0001'])
    end
  end

  it 'routes `archive read` and returns the body in JSON mode' do
    with_tmp_project do |root|
      task_id = archive_a_task(root)
      exit_code, stdout, = run(['archive', 'read', task_id, 'review', '--root', root.to_s, '--json'], cwd: root)
      expect(exit_code).to eq(0)
      body = JSON.parse(stdout)
      expect(body['artifact_key']).to eq('review')
      expect(body['body']).to include('review body')
    end
  end

  it 'prints the raw artifact body to stdout in --no-json mode' do
    with_tmp_project do |root|
      task_id = archive_a_task(root)
      exit_code, stdout, = run(['archive', 'read', task_id, 'review', '--root', root.to_s, '--no-json'], cwd: root)
      expect(exit_code).to eq(0)
      expect(stdout).to eq("# review body\nfindings here\n")
    end
  end

  it 'returns archived_artifact_not_found with available_keys for a missing key' do
    with_tmp_project do |root|
      task_id = archive_a_task(root)
      exit_code, _, stderr = run(['archive', 'read', task_id, 'nope', '--root', root.to_s, '--json'], cwd: root)
      expect(exit_code).to eq(1)
      err = JSON.parse(stderr)['error']
      expect(err['code']).to eq('archived_artifact_not_found')
      expect(err.dig('details', 'available_keys')).to include('review')
    end
  end

  it 'requires the TASK-ID positional for `archive show`' do
    with_tmp_project do |root|
      run(['init', '--root', root.to_s], cwd: root)
      exit_code, _, stderr = run(['archive', 'show', '--root', root.to_s, '--json'], cwd: root)
      expect(exit_code).to eq(1)
      expect(JSON.parse(stderr).dig('error', 'code')).to eq('invalid_arguments')
    end
  end

  it 'requires both positionals for `archive read`' do
    with_tmp_project do |root|
      run(['init', '--root', root.to_s], cwd: root)
      exit_code, _, stderr = run(['archive', 'read', 'TASK-0001', '--root', root.to_s, '--json'], cwd: root)
      expect(exit_code).to eq(1)
      expect(JSON.parse(stderr).dig('error', 'code')).to eq('invalid_arguments')
    end
  end

  it 'still archives a live task when the arg is a TASK-ID (backward compatible)' do
    with_tmp_project do |root|
      task_id = setup_project(root)
      %w[specify verify publish].each { |s| force_step_done(root, task_id, s) }
      exit_code, stdout, = run(['archive', task_id, '--root', root.to_s, '--json'], cwd: root)
      expect(exit_code).to eq(0)
      body = JSON.parse(stdout)
      expect(body['task_id']).to eq(task_id)
      expect(body['to']).to include('tasks/archive/')
      expect(Pathname.new("#{root}/tasks/#{task_id}").exist?).to be(false)
    end
  end
end
