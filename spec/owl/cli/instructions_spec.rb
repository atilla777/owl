# frozen_string_literal: true

require 'json'
require 'stringio'
require 'yaml'

require 'owl/cli/api'

RSpec.describe 'owl instructions CLI subcommand' do
  def run(argv, cwd:)
    stdout = StringIO.new
    stderr = StringIO.new
    exit_code = Owl::Cli::Api.run(argv: argv, stdout: stdout, stderr: stderr, env: {}, cwd: cwd.to_s)
    [exit_code, stdout.string, stderr.string]
  end

  def init_project(root)
    run(['init', '--root', root.to_s], cwd: root)
  end

  def seed_two_step_workflow(root)
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
      steps:
        - id: a
          skill: owl-step-discussion
          session_type: discussion
        - id: b
          skill: owl-step-discussion
          session_type: discussion
          requires: ["a"]
      artifacts: []
    YAML
  end

  def create_task(root)
    run(['task', 'create', '--workflow', 'feature', '--title', 't', '--root', root.to_s], cwd: root)
    'TASK-0001'
  end

  describe 'happy path' do
    it 'returns task, step, skill, invocation and summary as JSON' do # rubocop:disable RSpec/MultipleExpectations
      with_tmp_project do |root|
        init_project(root)
        seed_two_step_workflow(root)
        task_id = create_task(root)
        run(['task', 'use', task_id, '--root', root.to_s], cwd: root)

        exit_code, stdout, _stderr = run(['instructions', '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).to eq(0)
        body = JSON.parse(stdout)
        expect(body['ok']).to be(true)
        expect(body.dig('task', 'id')).to eq(task_id)
        expect(body.dig('task', 'workflow_key')).to eq('feature')
        expect(body.dig('step', 'id')).to eq('a')
        expect(body.dig('skill', 'id')).to eq('owl-step-discussion')
        expect(body.dig('skill', 'path')).to end_with('.claude/skills/owl-step-discussion/SKILL.md')
        expect(body.dig('skill', 'command_path')).to end_with('.claude/commands/owl-step-discussion.md')
        expect(body['summary']).to be_a(String)
        expect(body['summary']).not_to be_empty
        expect(body['invocation']).to include('task', 'step', 'inputs', 'outputs')
      end
    end

    it 'resolves explicit TASK-ID positional and --step-id option' do
      with_tmp_project do |root|
        init_project(root)
        seed_two_step_workflow(root)
        task_id = create_task(root)
        run(['step', 'start', task_id, 'a', '--root', root.to_s], cwd: root)
        run(['step', 'complete', task_id, 'a', '--root', root.to_s], cwd: root)

        exit_code, stdout, _stderr = run(
          ['instructions', task_id, '--step-id', 'b', '--root', root.to_s, '--json'],
          cwd: root
        )
        expect(exit_code).to eq(0)
        body = JSON.parse(stdout)
        expect(body.dig('step', 'id')).to eq('b')
        expect(body.dig('skill', 'id')).to eq('owl-step-discussion')
      end
    end
  end

  describe 'error paths' do
    it 'fails with no_current_task when pointer is empty and no positional task id' do
      with_tmp_project do |root|
        init_project(root)
        seed_two_step_workflow(root)
        exit_code, _stdout, stderr = run(['instructions', '--root', root.to_s], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('no_current_task')
      end
    end

    it 'fails with task_not_found for an unknown task id' do
      with_tmp_project do |root|
        init_project(root)
        seed_two_step_workflow(root)
        exit_code, _stdout, stderr = run(['instructions', 'TASK-9999', '--root', root.to_s], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('task_not_found')
      end
    end

    it 'fails with no_ready_steps when all workflow steps are done' do
      with_tmp_project do |root|
        init_project(root)
        write("#{root}/.owl/workflows.yaml", <<~YAML)
          schema_version: 1
          workflows:
            tiny:
              enabled: true
              source: "workflows/tiny/workflow.yaml"
        YAML
        write("#{root}/.owl/workflows/tiny/workflow.yaml", <<~YAML)
          id: tiny
          kind: task
          steps:
            - id: only
              skill: owl-step-discussion
              session_type: discussion
          artifacts: []
        YAML
        run(['task', 'create', '--workflow', 'tiny', '--title', 't', '--root', root.to_s], cwd: root)
        run(['step', 'start', 'TASK-0001', 'only', '--root', root.to_s], cwd: root)
        run(['step', 'complete', 'TASK-0001', 'only', '--root', root.to_s], cwd: root)

        exit_code, _stdout, stderr = run(['instructions', 'TASK-0001', '--root', root.to_s], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('no_ready_steps')
      end
    end

    it 'fails with step_not_ready when --step-id is not in the ready set' do
      with_tmp_project do |root|
        init_project(root)
        seed_two_step_workflow(root)
        task_id = create_task(root)
        # Step "b" requires "a" which is still pending.
        exit_code, _stdout, stderr = run(
          ['instructions', task_id, '--step-id', 'b', '--root', root.to_s],
          cwd: root
        )
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('step_not_ready')
      end
    end

    it 'fails with skill_not_found when the workflow step references an unmaterialized skill' do
      with_tmp_project do |root|
        init_project(root)
        write("#{root}/.owl/workflows.yaml", <<~YAML)
          schema_version: 1
          workflows:
            phantom:
              enabled: true
              source: "workflows/phantom/workflow.yaml"
        YAML
        write("#{root}/.owl/workflows/phantom/workflow.yaml", <<~YAML)
          id: phantom
          kind: task
          steps:
            - id: only
              skill: owl-step-phantom-never-shipped
              session_type: discussion
          artifacts: []
        YAML
        run(['task', 'create', '--workflow', 'phantom', '--title', 't', '--root', root.to_s], cwd: root)

        exit_code, _stdout, stderr = run(['instructions', 'TASK-0001', '--root', root.to_s], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('skill_not_found')
      end
    end
  end
end
