# frozen_string_literal: true

require 'stringio'

require 'owl/cli/api'
require 'owl/tasks/api'
require 'owl/tasks/internal/drift_scanner'

RSpec.describe Owl::Tasks::Internal::DriftScanner do
  def cli(argv, root)
    Owl::Cli::Api.run(argv: argv, stdout: StringIO.new, stderr: StringIO.new, env: {}, cwd: root.to_s)
  end

  # A single-step workflow: once that step is `done` the workflow is terminally
  # complete, but the task `status` stays whatever it was set to.
  def setup_project(root)
    cli(['init', '--root', root.to_s], root)
    write("#{root}/.owl/workflows.yaml", <<~YAML)
      schema_version: 1
      workflows:
        quick:
          enabled: true
          source: "workflows/quick/workflow.yaml"
    YAML
    write("#{root}/.owl/workflows/quick/workflow.yaml", <<~YAML)
      id: quick
      kind: task
      artifacts: {}
      steps:
        - id: build
        - id: ship
          requires: [build]
    YAML
    cli(['task', 'create', '--workflow', 'quick', '--title', 't', '--root', root.to_s, '--json'], root)
  end

  # Complete every step, then force the task status to `desired`. Completing the
  # terminal step auto-promotes the task to `done` via Steps::TaskFinalizer, so
  # to reproduce drift (the legacy / manually-reopened shape that `doctor`
  # targets) we set the status back afterwards.
  def complete_all_steps(root, task_id, status: nil)
    %w[build ship].each do |sid|
      cli(['step', 'start', task_id, sid, '--root', root.to_s, '--json'], root)
      cli(['step', 'complete', task_id, sid, '--root', root.to_s, '--json'], root)
    end
    cli(['task', 'set-status', task_id, status, '--root', root.to_s, '--json'], root) if status
  end

  def drifted(root)
    described_class.scan(root: root).value[:drifted]
  end

  it 'flags a workflow-complete task whose status is open' do
    with_tmp_project do |root|
      setup_project(root)
      complete_all_steps(root, 'TASK-0001', status: 'open')

      entry = drifted(root).first
      expect(entry).to include(
        task_id: 'TASK-0001',
        status: 'open',
        workflow: 'quick',
        terminal_step_id: 'ship',
        suggested_status: 'done'
      )
    end
  end

  it 'flags a workflow-complete task whose status is in_progress' do
    with_tmp_project do |root|
      setup_project(root)
      complete_all_steps(root, 'TASK-0001', status: 'in_progress')

      expect(drifted(root).map { |d| d[:task_id] }).to eq(['TASK-0001'])
      expect(drifted(root).first[:status]).to eq('in_progress')
    end
  end

  it 'does NOT flag an explicitly blocked task' do
    with_tmp_project do |root|
      setup_project(root)
      complete_all_steps(root, 'TASK-0001', status: 'blocked')

      expect(drifted(root)).to be_empty
    end
  end

  it 'does NOT flag an explicitly on_hold task' do
    with_tmp_project do |root|
      setup_project(root)
      complete_all_steps(root, 'TASK-0001', status: 'on_hold')

      expect(drifted(root)).to be_empty
    end
  end

  it 'does NOT flag an already-terminal (done) task' do
    with_tmp_project do |root|
      setup_project(root)
      # Completing the terminal step auto-promotes the task to `done`.
      complete_all_steps(root, 'TASK-0001')

      expect(drifted(root)).to be_empty
    end
  end

  it 'does NOT flag a task whose workflow still has a pending step' do
    with_tmp_project do |root|
      setup_project(root)
      cli(['step', 'start', 'TASK-0001', 'build', '--root', root.to_s, '--json'], root)
      cli(['step', 'complete', 'TASK-0001', 'build', '--root', root.to_s, '--json'], root)
      # `ship` is still pending → workflow not complete.

      expect(drifted(root)).to be_empty
    end
  end

  it 'is read-only: scanning does not mutate task.yaml status' do
    with_tmp_project do |root|
      setup_project(root)
      complete_all_steps(root, 'TASK-0001', status: 'open')

      before = File.read("#{root}/tasks/TASK-0001/task.yaml")
      drifted(root)
      after = File.read("#{root}/tasks/TASK-0001/task.yaml")

      expect(after).to eq(before)
    end
  end
end
