# frozen_string_literal: true

require 'json'
require 'stringio'

require 'owl/cli/api'

RSpec.describe 'owl artifact / owl step invocation CLI' do
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
        brief:
          type: brief
          storage:
            role: tasks
            path: "{{task.id}}/brief.md"
      steps:
        - id: brief
          title: Create brief
          skill: owl.steps.brief
          creates: [brief]
    YAML
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

    _, stdout, = run(['task', 'create', '--workflow', 'feature', '--title', 't',
                      '--root', root.to_s, '--json'], cwd: root)
    JSON.parse(stdout).dig('task', 'id')
  end

  describe 'artifact resolve' do
    it 'prints a resolved descriptor as JSON' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        exit_code, stdout, = run(['artifact', 'resolve', task_id, 'brief', '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).to eq(0)
        body = JSON.parse(stdout)
        expect(body['ok']).to be(true)
        expect(body['artifact']['key']).to eq('brief')
        expect(body['artifact']['type']).to eq('brief')
        expect(body['artifact']['exists']).to be(false)
        expect(body['artifact']['template_present']).to be(true)
      end
    end

    it 'returns unknown_workflow_artifact for an unknown key' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        exit_code, _, stderr = run(['artifact', 'resolve', task_id, 'nope', '--root', root.to_s], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('unknown_workflow_artifact')
      end
    end

    it 'returns invalid_arguments when positional args are missing' do
      with_tmp_project do |root|
        setup_project(root)
        exit_code, _, stderr = run(['artifact', 'resolve', '--root', root.to_s], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('invalid_arguments')
      end
    end

    it 'reports unknown_command for an unknown artifact subcommand' do
      with_tmp_project do |root|
        setup_project(root)
        exit_code, _, stderr = run(['artifact', 'nope', '--root', root.to_s], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('unknown_command')
      end
    end
  end

  describe 'artifact validate' do
    it 'returns valid: false JSON for a missing artifact file' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        exit_code, stdout, = run(['artifact', 'validate', task_id, 'brief', '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).to eq(0)
        body = JSON.parse(stdout)
        expect(body['ok']).to be(true)
        expect(body['valid']).to be(false)
        expect(body['violations'].first['type']).to eq('missing_artifact')
        expect(body.dig('artifact', 'key')).to eq('brief')
      end
    end

    it 'returns valid: true for a satisfied artifact' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        write("#{root}/tasks/#{task_id}/brief.md", "# Brief\n")
        exit_code, stdout, = run(['artifact', 'validate', task_id, 'brief', '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).to eq(0)
        body = JSON.parse(stdout)
        expect(body['valid']).to be(true)
        expect(body['violations']).to eq([])
      end
    end

    it 'aggregates results for the whole task when ARTIFACT-KEY is omitted' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        exit_code, stdout, = run(['artifact', 'validate', task_id, '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).to eq(0)
        body = JSON.parse(stdout)
        expect(body['ok']).to be(true)
        expect(body['all_valid']).to be(false)
        keys = body['results'].map { |r| r['artifact_key'] }
        expect(keys).to include('brief')
      end
    end

    it 'returns unknown_workflow_artifact for an unknown key' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        exit_code, _, stderr = run(['artifact', 'validate', task_id, 'nope', '--root', root.to_s], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('unknown_workflow_artifact')
      end
    end

    it 'returns invalid_arguments when TASK-ID is missing' do
      with_tmp_project do |root|
        setup_project(root)
        exit_code, _, stderr = run(['artifact', 'validate', '--root', root.to_s], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('invalid_arguments')
      end
    end
  end

  describe 'step invocation' do
    it 'prints a StepInvocation JSON with task, step, inputs, outputs' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        exit_code, stdout, = run(['step', 'invocation', task_id, 'brief', '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).to eq(0)
        body = JSON.parse(stdout)
        expect(body['ok']).to be(true)
        invocation = body['invocation']
        expect(invocation['schema_version']).to eq(1)
        expect(invocation.dig('task', 'id')).to eq(task_id)
        expect(invocation.dig('step', 'id')).to eq('brief')
        expect(invocation.dig('inputs', 'artifacts')).to eq({})
        expect(invocation.dig('outputs', 'artifacts')).to include('brief')
      end
    end

    it 'returns step_not_ready for a blocked step' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        write("#{root}/.owl/workflows/feature/workflow.yaml", <<~YAML)
          id: feature
          kind: task
          artifacts:
            brief:
              type: brief
              storage:
                role: tasks
                path: "{{task.id}}/brief.md"
          steps:
            - id: brief
              creates: [brief]
            - id: later
              requires: [brief]
        YAML
        exit_code, _, stderr = run(['step', 'invocation', task_id, 'later', '--root', root.to_s], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('step_not_ready')
      end
    end

    it 'fails with invalid_arguments when STEP-ID is missing' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        exit_code, _, stderr = run(['step', 'invocation', task_id, '--root', root.to_s], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('invalid_arguments')
      end
    end
  end
end
