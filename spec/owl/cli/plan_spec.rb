# frozen_string_literal: true

require 'json'
require 'stringio'
require 'yaml'

require 'owl/cli/api'
require 'owl/steps/api'

RSpec.describe 'owl plan CLI subcommands' do
  def run(argv, root)
    stdout = StringIO.new
    stderr = StringIO.new
    code = Owl::Cli::Api.run(
      argv: argv + ['--root', root.to_s], stdout: stdout, stderr: stderr, env: {}, cwd: root.to_s
    )
    [code, stdout.string, stderr.string]
  end

  def seed(root)
    run(['init'], root)
    write("#{root}/.owl/workflows.yaml", <<~YAML)
      schema_version: 1
      workflows:
        feat:
          enabled: true
          source: "workflows/feat/workflow.yaml"
    YAML
    write("#{root}/.owl/artifacts.yaml", <<~YAML)
      schema_version: 1
      artifacts:
        plan:
          source: "artifacts/plan/artifact.yaml"
    YAML
    write("#{root}/.owl/artifacts/plan/artifact.yaml", <<~YAML)
      id: plan
      kind: markdown
      default_template: templates/default.md
    YAML
    write("#{root}/.owl/artifacts/plan/templates/default.md", "# Plan\n")
    write("#{root}/.owl/workflows/feat/workflow.yaml", <<~YAML)
      id: feat
      kind: task
      artifacts:
        plan:
          type: plan
          storage:
            role: tasks
            path: "{{task.id}}/plan.md"
      steps:
        - id: plan
          session_type: discussion
          creates: [plan]
        - id: implement
          session_type: execution
          requires: [plan]
          gate: plan_approved
    YAML
    run(['task', 'create', '--workflow', 'feat', '--title', 't'], root)
    'TASK-0001'
  end

  def complete_plan(root, task_id)
    write("#{root}/tasks/#{task_id}/plan.md", "# the plan\n")
    Owl::Steps::Api.start(root: root, task_id: task_id, step_id: 'plan')
    Owl::Steps::Api.complete(root: root, task_id: task_id, step_id: 'plan')
  end

  it 'owl plan status reports gate_open false before approval, true after' do
    with_tmp_project do |root|
      task_id = seed(root)
      complete_plan(root, task_id)

      code, out, = run(['plan', 'status', task_id, '--json'], root)
      expect(code).to eq(0)
      body = JSON.parse(out)
      expect(body).to include('ok' => true, 'task_id' => task_id, 'approved' => false, 'gate_open' => false)

      acode, aout, = run(['plan', 'approve', task_id, '--json'], root)
      expect(acode).to eq(0)
      abody = JSON.parse(aout)
      expect(abody['ok']).to be(true)
      expect(abody.dig('plan_approval', 'approved')).to be(true)
      expect(abody.dig('plan_approval', 'plan_sha')).to be_a(String)

      _c, sout, = run(['plan', 'status', task_id, '--json'], root)
      expect(JSON.parse(sout)).to include('approved' => true, 'gate_open' => true)
    end
  end

  it 'owl plan approve fails with plan_not_completed before the plan step is done' do
    with_tmp_project do |root|
      task_id = seed(root)
      _code, _out, err = run(['plan', 'approve', task_id, '--json'], root)
      expect(JSON.parse(err).dig('error', 'code')).to eq('plan_not_completed')
    end
  end

  it 'owl plan approve requires a TASK-ID positional' do
    with_tmp_project do |root|
      seed(root)
      _code, _out, err = run(['plan', 'approve', '--json'], root)
      expect(JSON.parse(err).dig('error', 'code')).to eq('invalid_arguments')
    end
  end

  it 'rejects an unknown plan subcommand' do
    with_tmp_project do |root|
      seed(root)
      _code, _out, err = run(%w[plan frobnicate], root)
      expect(JSON.parse(err).dig('error', 'code')).to eq('unknown_command')
    end
  end

  it 'owl next returns await_plan_approval while the gate holds, dispatch_step after approval' do
    with_tmp_project do |root|
      task_id = seed(root)
      complete_plan(root, task_id)

      _c, out, = run(['next', task_id, '--json'], root)
      body = JSON.parse(out)
      expect(body.dig('action', 'kind')).to eq('await_plan_approval')
      expect(body.dig('action', 'step_id')).to eq('implement')
      expect(body.dig('action', 'blocker')).to include('plan approve')

      run(['plan', 'approve', task_id, '--json'], root)
      _c2, out2, = run(['next', task_id, '--json'], root)
      expect(JSON.parse(out2).dig('action', 'kind')).to eq('dispatch_step')
    end
  end
end
