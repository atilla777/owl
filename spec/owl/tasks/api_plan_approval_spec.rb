# frozen_string_literal: true

require 'json'
require 'stringio'
require 'yaml'

require 'owl/cli/api'
require 'owl/tasks/api'
require 'owl/steps/api'

RSpec.describe Owl::Tasks::Api, '.approve_plan / .plan_status' do
  def run_cli(argv, root)
    stdout = StringIO.new
    stderr = StringIO.new
    Owl::Cli::Api.run(argv: argv + ['--root', root.to_s], stdout: stdout, stderr: stderr, env: {}, cwd: root.to_s)
    [stdout.string, stderr.string]
  end

  def seed(root)
    run_cli(['init'], root)
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
  end

  def create_task(root)
    run_cli(['task', 'create', '--workflow', 'feat', '--title', 't'], root)
    'TASK-0001'
  end

  def complete_plan(root, task_id)
    write("#{root}/tasks/#{task_id}/plan.md", "# the plan body\n")
    Owl::Steps::Api.start(root: root, task_id: task_id, step_id: 'plan')
    Owl::Steps::Api.complete(root: root, task_id: task_id, step_id: 'plan')
  end

  it 'approves a completed plan and opens the gate' do
    with_tmp_project do |root|
      seed(root)
      task_id = create_task(root)
      complete_plan(root, task_id)

      result = described_class.approve_plan(root: root, task_id: task_id)
      expect(result).to be_ok
      expect(result.value[:plan_approval][:approved]).to be(true)
      expect(result.value[:plan_approval][:plan_sha]).to be_a(String)

      status = described_class.plan_status(root: root, task_id: task_id)
      expect(status.value[:approved]).to be(true)
      expect(status.value[:gate_open]).to be(true)
    end
  end

  it 'is idempotent for an already-approved plan' do
    with_tmp_project do |root|
      seed(root)
      task_id = create_task(root)
      complete_plan(root, task_id)

      first = described_class.approve_plan(root: root, task_id: task_id)
      second = described_class.approve_plan(root: root, task_id: task_id)
      expect(second).to be_ok
      expect(second.value[:plan_approval][:plan_sha]).to eq(first.value[:plan_approval][:plan_sha])
      expect(second.value[:plan_approval][:approved_at]).to eq(first.value[:plan_approval][:approved_at])
    end
  end

  it 'refuses approval when the plan step is not done' do
    with_tmp_project do |root|
      seed(root)
      task_id = create_task(root)

      result = described_class.approve_plan(root: root, task_id: task_id)
      expect(result).to be_err
      expect(result.code).to eq(:plan_not_completed)
    end
  end

  it 'returns unknown_task for a missing task' do
    with_tmp_project do |root|
      seed(root)
      result = described_class.approve_plan(root: root, task_id: 'TASK-9999')
      expect(result).to be_err
      expect(result.code).to eq(:unknown_task)

      status = described_class.plan_status(root: root, task_id: 'TASK-9999')
      expect(status).to be_err
      expect(status.code).to eq(:unknown_task)
    end
  end

  it 'rejects approval when a different live session holds the claim' do
    with_tmp_project do |root|
      seed(root)
      task_id = create_task(root)
      complete_plan(root, task_id)
      claim = described_class.claim(root: root, task_id: task_id)
      token = claim.value[:token]

      held = described_class.approve_plan(root: root, task_id: task_id, token: 'someone-else')
      expect(held).to be_err
      expect(held.code).to eq(:lease_held)

      # The owning session can approve.
      owner = described_class.approve_plan(root: root, task_id: task_id, token: token)
      expect(owner).to be_ok
    end
  end

  it 'reports gate closed before approval' do
    with_tmp_project do |root|
      seed(root)
      task_id = create_task(root)
      complete_plan(root, task_id)

      status = described_class.plan_status(root: root, task_id: task_id)
      expect(status.value[:approved]).to be(false)
      expect(status.value[:gate_open]).to be(false)
    end
  end
end
