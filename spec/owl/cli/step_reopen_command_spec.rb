# frozen_string_literal: true

require 'json'
require 'stringio'
require 'yaml'

require 'owl/cli/api'

RSpec.describe 'owl step reopen CLI subcommand' do
  def run(argv, cwd:)
    stdout = StringIO.new
    stderr = StringIO.new
    exit_code = Owl::Cli::Api.run(argv: argv, stdout: stdout, stderr: stderr, env: {}, cwd: cwd.to_s)
    [exit_code, stdout.string, stderr.string]
  end

  def setup_project(root, with_artifact: false)
    run(['init', '--root', root.to_s], cwd: root)
    write("#{root}/.owl/workflows.yaml", <<~YAML)
      schema_version: 1
      workflows:
        feature:
          enabled: true
          source: "workflows/feature/workflow.yaml"
    YAML
    if with_artifact
      write("#{root}/.owl/artifacts.yaml", <<~YAML)
        schema_version: 1
        artifacts:
          brief:
            source: "artifacts/brief/artifact.yaml"
      YAML
      write("#{root}/.owl/artifacts/brief/artifact.yaml", "id: brief\nkind: markdown\n")
    end
    write("#{root}/.owl/workflows/feature/workflow.yaml", workflow_body(with_artifact: with_artifact))
    run(['task', 'create', '--workflow', 'feature', '--title', 't', '--root', root.to_s], cwd: root)
    'TASK-0001'
  end

  def workflow_body(with_artifact:)
    if with_artifact
      <<~YAML
        id: feature
        kind: task
        artifacts:
          brief:
            type: brief
            storage:
              role: tasks
              path: "{{task.id}}/brief.md"
        steps:
          - id: a
            creates: [brief]
            drift_policy: warn
          - id: b
            requires: [a]
            drift_policy: warn
      YAML
    else
      <<~YAML
        id: feature
        kind: feature
        artifacts: []
        steps:
          - id: a
          - id: b
            requires: [a]
      YAML
    end
  end

  def complete_step(root, task_id, step_id, body: "# body\n")
    write("#{root}/tasks/#{task_id}/brief.md", body) if step_id == 'a'
    run(['step', 'start', task_id, step_id, '--root', root.to_s], cwd: root)
    run(['step', 'complete', task_id, step_id, '--root', root.to_s], cwd: root)
  end

  it 'reopens a done step without cascade' do
    with_tmp_project do |root|
      task_id = setup_project(root)
      complete_step(root, task_id, 'a')
      complete_step(root, task_id, 'b')

      exit_code, stdout, = run(['step', 'reopen', task_id, 'a', '--root', root.to_s, '--json'], cwd: root)
      expect(exit_code).to eq(0)
      body = JSON.parse(stdout)
      expect(body['ok']).to be(true)
      expect(body['reopened']).to eq(['a'])

      task = YAML.safe_load_file("#{root}/tasks/#{task_id}/task.yaml")
      expect(task['steps'].find { |s| s['id'] == 'a' }['status']).to eq('pending')
      expect(task['steps'].find { |s| s['id'] == 'b' }['status']).to eq('done')
    end
  end

  it 'reopens transitively with --cascade' do
    with_tmp_project do |root|
      task_id = setup_project(root)
      complete_step(root, task_id, 'a')
      complete_step(root, task_id, 'b')

      exit_code, stdout, = run(['step', 'reopen', task_id, 'a', '--cascade', '--root', root.to_s, '--json'], cwd: root)
      expect(exit_code).to eq(0)
      expect(JSON.parse(stdout)['reopened']).to contain_exactly('a', 'b')
    end
  end

  it 'fails with invalid_arguments when TASK-ID is missing' do
    with_tmp_project do |root|
      setup_project(root)
      exit_code, _stdout, stderr = run(['step', 'reopen', '--root', root.to_s], cwd: root)
      expect(exit_code).to eq(1)
      expect(JSON.parse(stderr).dig('error', 'code')).to eq('invalid_arguments')
    end
  end

  it 'fails with step_not_completed when the step is not done' do
    with_tmp_project do |root|
      task_id = setup_project(root)
      exit_code, _stdout, stderr = run(['step', 'reopen', task_id, 'a', '--root', root.to_s], cwd: root)
      expect(exit_code).to eq(1)
      expect(JSON.parse(stderr).dig('error', 'code')).to eq('step_not_completed')
    end
  end

  it 'prints artifact_modified_after_complete warning on step start after file change' do
    with_tmp_project do |root|
      task_id = setup_project(root, with_artifact: true)
      complete_step(root, task_id, 'a')
      run(['step', 'reopen', task_id, 'a', '--root', root.to_s], cwd: root)
      write("#{root}/tasks/#{task_id}/brief.md", "# modified outside\n")

      exit_code, _stdout, stderr = run(['step', 'start', task_id, 'a', '--root', root.to_s], cwd: root)
      expect(exit_code).to eq(0)
      expect(stderr).to include('artifact_modified_after_complete')
      expect(stderr).to include('step=a')
      expect(stderr).to include('artifact=brief')
    end
  end

  it 'blocks step start when drift_policy defaults to block (execution session_type)' do
    with_tmp_project do |root|
      task_id = setup_project(root, with_artifact: true)
      # Override the fixture to drop drift_policy from step a so the default kicks in.
      File.write(
        "#{root}/.owl/workflows/feature/workflow.yaml",
        <<~YAML
          id: feature
          kind: task
          artifacts:
            brief:
              type: brief
              storage: { role: tasks, path: "{{task.id}}/brief.md" }
          steps:
            - id: a
              creates: [brief]
            - id: b
              requires: [a]
        YAML
      )
      complete_step(root, task_id, 'a')
      run(['step', 'reopen', task_id, 'a', '--root', root.to_s], cwd: root)
      write("#{root}/tasks/#{task_id}/brief.md", "# modified outside\n")

      exit_code, _stdout, stderr = run(['step', 'start', task_id, 'a', '--root', root.to_s], cwd: root)
      expect(exit_code).to eq(2)
      payload = JSON.parse(stderr)
      expect(payload.dig('error', 'code')).to eq('drift_block')
      expect(payload.dig('error', 'details', 'step_id')).to eq('a')
    end
  end

  it 'suppresses drift warning with --ignore-modification' do
    with_tmp_project do |root|
      task_id = setup_project(root, with_artifact: true)
      complete_step(root, task_id, 'a')
      run(['step', 'reopen', task_id, 'a', '--root', root.to_s], cwd: root)
      write("#{root}/tasks/#{task_id}/brief.md", "# modified outside\n")

      exit_code, _stdout, stderr = run(
        ['step', 'start', task_id, 'a', '--ignore-modification', '--root', root.to_s], cwd: root
      )
      expect(exit_code).to eq(0)
      expect(stderr).not_to include('artifact_modified_after_complete')
    end
  end
end
