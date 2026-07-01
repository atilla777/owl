# frozen_string_literal: true

require 'json'
require 'stringio'
require 'yaml'

require 'owl/cli/api'
require 'owl/tasks/api'
require 'owl/steps/api'
require 'owl/workflows/api'

RSpec.describe Owl::Workflows::Api, '.ready_steps plan-approval gate' do
  def run_cli(argv, root)
    stdout = StringIO.new
    stderr = StringIO.new
    Owl::Cli::Api.run(argv: argv + ['--root', root.to_s], stdout: stdout, stderr: stderr, env: {}, cwd: root.to_s)
    [stdout.string, stderr.string]
  end

  def write_plan_artifact_registry(root)
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
  end

  def plan_artifact_block
    <<~YAML.chomp
      artifacts:
        plan:
          type: plan
          storage:
            role: tasks
            path: "{{task.id}}/plan.md"
    YAML
  end

  def complete_plan(root, task_id)
    write("#{root}/tasks/#{task_id}/plan.md", "# real plan\n")
    Owl::Steps::Api.start(root: root, task_id: task_id, step_id: 'plan')
    Owl::Steps::Api.complete(root: root, task_id: task_id, step_id: 'plan')
  end

  context 'with the gate declared on implement' do
    def seed_gated(root)
      run_cli(['init'], root)
      write("#{root}/.owl/workflows.yaml", <<~YAML)
        schema_version: 1
        workflows:
          feat:
            enabled: true
            source: "workflows/feat/workflow.yaml"
      YAML
      write_plan_artifact_registry(root)
      write("#{root}/.owl/workflows/feat/workflow.yaml", <<~YAML)
        id: feat
        kind: task
        #{plan_artifact_block}
        steps:
          - id: plan
            session_type: discussion
            creates: [plan]
          - id: implement
            session_type: execution
            requires: [plan]
            gate: plan_approved
      YAML
      run_cli(['task', 'create', '--workflow', 'feat', '--title', 't'], root)
      'TASK-0001'
    end

    it 'holds implement out of ready and surfaces it under awaiting_plan_approval' do
      with_tmp_project do |root|
        task_id = seed_gated(root)
        complete_plan(root, task_id)

        result = described_class.ready_steps(root: root, task_id: task_id)
        expect(result).to be_ok
        expect(result.value[:ready].map { |s| s[:id] }).not_to include('implement')
        expect(result.value[:awaiting_plan_approval]).to eq(['implement'])
      end
    end

    it 'releases implement once the plan is approved' do
      with_tmp_project do |root|
        task_id = seed_gated(root)
        complete_plan(root, task_id)
        Owl::Tasks::Api.approve_plan(root: root, task_id: task_id)

        result = described_class.ready_steps(root: root, task_id: task_id)
        expect(result.value[:ready].map { |s| s[:id] }).to eq(['implement'])
        expect(result.value[:awaiting_plan_approval]).to eq([])
      end
    end

    it 're-holds implement after the plan step is reopened (approval reset)' do
      with_tmp_project do |root|
        task_id = seed_gated(root)
        complete_plan(root, task_id)
        Owl::Tasks::Api.approve_plan(root: root, task_id: task_id)
        Owl::Steps::Api.reopen(root: root, task_id: task_id, step_id: 'plan', cascade: true)
        complete_plan(root, task_id)

        result = described_class.ready_steps(root: root, task_id: task_id)
        expect(result.value[:ready].map { |s| s[:id] }).not_to include('implement')
        expect(result.value[:awaiting_plan_approval]).to eq(['implement'])
      end
    end
  end

  context 'without the gate declared (regression)' do
    it 'dispatches implement immediately after plan completes' do
      with_tmp_project do |root|
        run_cli(['init'], root)
        write("#{root}/.owl/workflows.yaml", <<~YAML)
          schema_version: 1
          workflows:
            feat:
              enabled: true
              source: "workflows/feat/workflow.yaml"
        YAML
        write_plan_artifact_registry(root)
        write("#{root}/.owl/workflows/feat/workflow.yaml", <<~YAML)
          id: feat
          kind: task
          #{plan_artifact_block}
          steps:
            - id: plan
              session_type: discussion
              creates: [plan]
            - id: implement
              session_type: execution
              requires: [plan]
        YAML
        run_cli(['task', 'create', '--workflow', 'feat', '--title', 't'], root)
        complete_plan(root, 'TASK-0001')

        result = described_class.ready_steps(root: root, task_id: 'TASK-0001')
        expect(result.value[:ready].map { |s| s[:id] }).to eq(['implement'])
        expect(result.value[:awaiting_plan_approval]).to eq([])
      end
    end
  end

  context 'with the per-task require_plan_approval opt-in (no YAML gate)' do
    def seed_ungated(root)
      run_cli(['init'], root)
      write("#{root}/.owl/workflows.yaml", <<~YAML)
        schema_version: 1
        workflows:
          feat:
            enabled: true
            source: "workflows/feat/workflow.yaml"
      YAML
      write_plan_artifact_registry(root)
      write("#{root}/.owl/workflows/feat/workflow.yaml", <<~YAML)
        id: feat
        kind: task
        #{plan_artifact_block}
        steps:
          - id: plan
            session_type: discussion
            creates: [plan]
          - id: implement
            session_type: execution
            requires: [plan]
      YAML
    end

    it 'holds implement when the task opted in, even without a YAML gate' do
      with_tmp_project do |root|
        seed_ungated(root)
        run_cli(['task', 'create', '--workflow', 'feat', '--title', 't', '--require-plan-approval'], root)
        complete_plan(root, 'TASK-0001')

        result = described_class.ready_steps(root: root, task_id: 'TASK-0001')
        expect(result.value[:ready].map { |s| s[:id] }).not_to include('implement')
        expect(result.value[:awaiting_plan_approval]).to eq(['implement'])
      end
    end

    it 'releases implement once the opted-in plan is approved' do
      with_tmp_project do |root|
        seed_ungated(root)
        run_cli(['task', 'create', '--workflow', 'feat', '--title', 't', '--require-plan-approval'], root)
        complete_plan(root, 'TASK-0001')
        Owl::Tasks::Api.approve_plan(root: root, task_id: 'TASK-0001')

        result = described_class.ready_steps(root: root, task_id: 'TASK-0001')
        expect(result.value[:ready].map { |s| s[:id] }).to eq(['implement'])
        expect(result.value[:awaiting_plan_approval]).to eq([])
      end
    end

    it 'does not hold implement when the task did not opt in' do
      with_tmp_project do |root|
        seed_ungated(root)
        run_cli(['task', 'create', '--workflow', 'feat', '--title', 't'], root)
        complete_plan(root, 'TASK-0001')

        result = described_class.ready_steps(root: root, task_id: 'TASK-0001')
        expect(result.value[:ready].map { |s| s[:id] }).to eq(['implement'])
        expect(result.value[:awaiting_plan_approval]).to eq([])
      end
    end

    it 'honours the settings.plan_approval.required config default' do
      with_tmp_project do |root|
        seed_ungated(root)
        run_cli(['config', 'set', 'settings.plan_approval.required', 'true'], root)
        run_cli(['task', 'create', '--workflow', 'feat', '--title', 't'], root)
        complete_plan(root, 'TASK-0001')

        result = described_class.ready_steps(root: root, task_id: 'TASK-0001')
        expect(result.value[:awaiting_plan_approval]).to eq(['implement'])
      end
    end

    it 'lets --no-require-plan-approval override the config default' do
      with_tmp_project do |root|
        seed_ungated(root)
        run_cli(['config', 'set', 'settings.plan_approval.required', 'true'], root)
        run_cli(['task', 'create', '--workflow', 'feat', '--title', 't', '--no-require-plan-approval'], root)
        complete_plan(root, 'TASK-0001')

        result = described_class.ready_steps(root: root, task_id: 'TASK-0001')
        expect(result.value[:awaiting_plan_approval]).to eq([])
      end
    end
  end

  context 'with both plan_approved and children_complete on a composite' do
    def seed_composite(root)
      run_cli(['init'], root)
      write("#{root}/.owl/workflows.yaml", <<~YAML)
        schema_version: 1
        workflows:
          comp:
            enabled: true
            source: "workflows/comp/workflow.yaml"
          leaf:
            enabled: true
            source: "workflows/leaf/workflow.yaml"
      YAML
      write_plan_artifact_registry(root)
      write("#{root}/.owl/workflows/comp/workflow.yaml", <<~YAML)
        id: comp
        kind: composite_task
        #{plan_artifact_block}
        steps:
          - id: plan
            session_type: discussion
            creates: [plan]
          - id: implement
            session_type: execution
            requires: [plan]
            gate: plan_approved
          - id: finalize
            session_type: execution
            requires: [plan]
            gate: children_complete
      YAML
      write("#{root}/.owl/workflows/leaf/workflow.yaml", <<~YAML)
        id: leaf
        kind: task
        steps:
          - id: do
            session_type: execution
        artifacts: []
      YAML
      run_cli(['task', 'create', '--workflow', 'comp', '--title', 'P'], root)
      run_cli(['task', 'create', '--workflow', 'leaf', '--title', 'C', '--parent', 'TASK-0001'], root)
      'TASK-0001'
    end

    it 'routes the plan_approved step and the children_complete step to separate buckets' do
      with_tmp_project do |root|
        parent = seed_composite(root)
        complete_plan(root, parent)

        result = described_class.ready_steps(root: root, task_id: parent)
        expect(result).to be_ok
        expect(result.value[:awaiting_plan_approval]).to eq(['implement'])
        expect(result.value[:blocked_by_children]).to eq(['finalize'])
        expect(result.value[:ready].map { |s| s[:id] }).not_to include('implement', 'finalize')
      end
    end
  end
end
