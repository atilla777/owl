# frozen_string_literal: true

require 'json'
require 'stringio'
require 'yaml'

require 'owl/cli/api'
require 'owl/steps/api'

RSpec.describe Owl::Steps::Api, '.reopen' do
  def run_cli(argv, cwd:)
    Owl::Cli::Api.run(
      argv: argv, stdout: StringIO.new, stderr: StringIO.new, env: {}, cwd: cwd.to_s
    )
  end

  def setup_project(root, with_artifact: true)
    run_cli(['init', '--root', root.to_s], cwd: root)
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
      write("#{root}/.owl/artifacts/brief/artifact.yaml", <<~YAML)
        id: brief
        kind: markdown
        default_template: templates/default.md
      YAML
      write("#{root}/.owl/artifacts/brief/templates/default.md", "# Brief\n")
    end
    write("#{root}/.owl/workflows/feature/workflow.yaml", workflow_yaml(with_artifact: with_artifact))
    stdout = StringIO.new
    Owl::Cli::Api.run(
      argv: ['task', 'create', '--workflow', 'feature', '--title', 't', '--root', root.to_s, '--json'],
      stdout: stdout, stderr: StringIO.new, env: {}, cwd: root.to_s
    )
    JSON.parse(stdout.string).dig('task', 'id')
  end

  def workflow_yaml(with_artifact:)
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
          - id: b
            requires: [a]
          - id: c
            requires: [b]
      YAML
    else
      <<~YAML
        id: feature
        kind: task
        artifacts: {}
        steps:
          - id: a
          - id: b
            requires: [a]
          - id: c
            requires: [b]
      YAML
    end
  end

  def task_yaml(root, task_id)
    YAML.safe_load_file("#{root}/tasks/#{task_id}/task.yaml")
  end

  def step_status(root, task_id, step_id)
    task_yaml(root, task_id)['steps'].find { |s| s['id'] == step_id }['status']
  end

  def complete_step(root, task_id, step_id)
    write("#{root}/tasks/#{task_id}/brief.md", "# brief body\n") if step_id == 'a'
    Owl::Steps::Api.start(root: root, task_id: task_id, step_id: step_id)
    Owl::Steps::Api.complete(root: root, task_id: task_id, step_id: step_id)
  end

  it 'moves a done step back to pending' do
    with_tmp_project do |root|
      task_id = setup_project(root, with_artifact: false)
      complete_step(root, task_id, 'a')

      result = described_class.reopen(root: root, task_id: task_id, step_id: 'a')
      expect(result).to be_ok
      expect(result.value[:reopened]).to eq(['a'])
      expect(step_status(root, task_id, 'a')).to eq('pending')
    end
  end

  it 'preserves content_sha when reopening' do
    with_tmp_project do |root|
      task_id = setup_project(root)
      complete_step(root, task_id, 'a')
      sha_before = task_yaml(root, task_id)['steps'].find { |s| s['id'] == 'a' }['content_sha']
      expect(sha_before).to be_a(String)

      described_class.reopen(root: root, task_id: task_id, step_id: 'a')

      step = task_yaml(root, task_id)['steps'].find { |s| s['id'] == 'a' }
      expect(step['status']).to eq('pending')
      expect(step['content_sha']).to eq(sha_before)
    end
  end

  it 'fails with step_not_completed when step is not done' do
    with_tmp_project do |root|
      task_id = setup_project(root, with_artifact: false)
      result = described_class.reopen(root: root, task_id: task_id, step_id: 'a')
      expect(result).to be_err
      expect(result.code).to eq(:step_not_completed)
    end
  end

  it 'fails with unknown_step_id for an unknown step' do
    with_tmp_project do |root|
      task_id = setup_project(root, with_artifact: false)
      result = described_class.reopen(root: root, task_id: task_id, step_id: 'ghost')
      expect(result).to be_err
      expect(result.code).to eq(:unknown_step_id)
    end
  end

  it 'fails with artifact_missing when the artifact file has been deleted' do
    with_tmp_project do |root|
      task_id = setup_project(root)
      complete_step(root, task_id, 'a')
      File.delete("#{root}/tasks/#{task_id}/brief.md")

      result = described_class.reopen(root: root, task_id: task_id, step_id: 'a')
      expect(result).to be_err
      expect(result.code).to eq(:artifact_missing)
      expect(step_status(root, task_id, 'a')).to eq('done')
    end
  end

  it 'cascade pendifies all transitive downstream done steps' do
    with_tmp_project do |root|
      task_id = setup_project(root, with_artifact: false)
      complete_step(root, task_id, 'a')
      complete_step(root, task_id, 'b')
      complete_step(root, task_id, 'c')

      result = described_class.reopen(root: root, task_id: task_id, step_id: 'a', cascade: true)
      expect(result).to be_ok
      expect(result.value[:reopened]).to contain_exactly('a', 'b', 'c')
      expect(step_status(root, task_id, 'a')).to eq('pending')
      expect(step_status(root, task_id, 'b')).to eq('pending')
      expect(step_status(root, task_id, 'c')).to eq('pending')
    end
  end

  it 'cascade skips downstream steps that are not done' do
    with_tmp_project do |root|
      task_id = setup_project(root, with_artifact: false)
      complete_step(root, task_id, 'a')
      complete_step(root, task_id, 'b')

      result = described_class.reopen(root: root, task_id: task_id, step_id: 'a', cascade: true)
      expect(result).to be_ok
      expect(result.value[:reopened]).to contain_exactly('a', 'b')
      expect(step_status(root, task_id, 'c')).to eq('pending')
    end
  end

  # The cascade reopen_targets guard is defensive: the public `reopen` path already rejects a
  # missing workflow key earlier (artifact resolution / inspect), so the only way to reach the
  # guard is an inspect payload that lacks `workflow.key`. Stub inspect to exercise it directly.
  it 'reopen_targets errors with task_workflow_missing when the payload has no workflow key' do
    allow(Owl::Tasks::Api).to receive(:inspect).and_return(
      Owl::Result.ok(payload: { 'steps' => [{ 'id' => 'a', 'status' => 'done' }] })
    )

    result = described_class.reopen_targets(root: '/anywhere', task_id: 'TASK-0001', step_id: 'a', cascade: true)

    expect(result).to be_err
    expect(result.code).to eq(:task_workflow_missing)
  end
end
