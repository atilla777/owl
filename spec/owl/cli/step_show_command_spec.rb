# frozen_string_literal: true

require 'json'
require 'stringio'

require 'owl/cli/api'

RSpec.describe 'owl step show CLI subcommand' do
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
      artifacts: []
      steps:
        - id: a
          context: "do step a"
        - id: b
          requires: ["a"]
    YAML
    _, stdout, = run(['task', 'create', '--workflow', 'feature', '--title', 't',
                      '--root', root.to_s, '--json'], cwd: root)
    JSON.parse(stdout).dig('task', 'id')
  end

  it 'prints the merged bundle as JSON on the happy path' do
    with_tmp_project do |root|
      task_id = setup_project(root)
      exit_code, stdout, = run(['step', 'show', task_id, 'a', '--root', root.to_s, '--json'], cwd: root)
      expect(exit_code).to eq(0)
      body = JSON.parse(stdout)
      expect(body['ok']).to be(true)
      expect(body.dig('bundle', 'step', 'id')).to eq('a')
      expect(body.dig('bundle', 'context')).to eq('do step a')
      expect(body.dig('bundle', 'task', 'id')).to eq(task_id)
    end
  end

  it 'fails with invalid_arguments when positional args are missing' do
    with_tmp_project do |root|
      setup_project(root)
      exit_code, _, stderr = run(['step', 'show', '--root', root.to_s], cwd: root)
      expect(exit_code).to eq(1)
      expect(JSON.parse(stderr).dig('error', 'code')).to eq('invalid_arguments')
    end
  end

  it 'fails with task_not_found when the task does not exist' do
    with_tmp_project do |root|
      setup_project(root)
      exit_code, _, stderr = run(['step', 'show', 'TASK-9999', 'a', '--root', root.to_s], cwd: root)
      expect(exit_code).to eq(1)
      expect(JSON.parse(stderr).dig('error', 'code')).to eq('task_not_found')
    end
  end

  it 'fails with unknown_step_id when the step is not in the workflow' do
    with_tmp_project do |root|
      task_id = setup_project(root)
      exit_code, _, stderr = run(['step', 'show', task_id, 'nope', '--root', root.to_s], cwd: root)
      expect(exit_code).to eq(1)
      expect(JSON.parse(stderr).dig('error', 'code')).to eq('unknown_step_id')
    end
  end
end
