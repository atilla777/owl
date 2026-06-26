# frozen_string_literal: true

require 'json'
require 'stringio'

require 'owl/cli/api'

# Cross-command guard (TASK-0043): `next` / `status` / `ready-steps` /
# `instructions` invoked with an EXPLICIT terminal task id must reject with the
# structured `task_terminal` code and a non-zero exit, instead of pretending the
# dead task is runnable. The reject applies ONLY to explicitly-passed ids.
RSpec.describe 'terminal-task CLI guard' do
  def run(argv, cwd:)
    stdout = StringIO.new
    stderr = StringIO.new
    exit_code = Owl::Cli::Api.run(argv: argv, stdout: stdout, stderr: stderr, env: {}, cwd: cwd.to_s)
    [exit_code, stdout.string, stderr.string]
  end

  def seed(root)
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
      steps:
        - id: a
          skill: owl-step-discussion
          session_type: discussion
      artifacts: []
    YAML
  end

  def abandoned_task(root)
    run(['task', 'create', '--workflow', 'feature', '--title', 't', '--root', root.to_s, '--json'], cwd: root)
    run(['task', 'abandon', 'TASK-0001', '--root', root.to_s, '--json'], cwd: root)
    'TASK-0001'
  end

  # Seed a work -> archive -> commit_push workflow and drive TASK-0001 up to (and
  # including) a completed `archive` step, so the task is status `archived` with
  # only the terminal `commit_push` step still pending.
  def archived_midflow_task(root)
    run(['init', '--root', root.to_s], cwd: root)
    write("#{root}/.owl/workflows.yaml", <<~YAML)
      schema_version: 1
      workflows:
        feat:
          enabled: true
          source: "workflows/feat/workflow.yaml"
    YAML
    write("#{root}/.owl/workflows/feat/workflow.yaml", <<~YAML)
      id: feat
      kind: task
      artifacts: {}
      steps:
        - id: work
          session_type: execution
        - id: archive
          session_type: execution
          requires: ["work"]
        - id: commit_push
          session_type: execution
          requires: ["archive"]
    YAML
    run(['task', 'create', '--workflow', 'feat', '--title', 't', '--root', root.to_s, '--json'], cwd: root)
    %w[work].each do |s|
      run(['step', 'start', 'TASK-0001', s, '--root', root.to_s, '--json'], cwd: root)
      run(['step', 'complete', 'TASK-0001', s, '--root', root.to_s, '--json'], cwd: root)
    end
    run(['step', 'start', 'TASK-0001', 'archive', '--root', root.to_s, '--json'], cwd: root)
    run(['archive', 'TASK-0001', '--root', root.to_s, '--json'], cwd: root)
    run(['step', 'complete', 'TASK-0001', 'archive', '--root', root.to_s, '--json'], cwd: root)
    'TASK-0001'
  end

  shared_examples 'rejects an explicit terminal id' do |argv_for|
    it 'returns ok:false / code task_terminal with a non-zero exit' do
      with_tmp_project do |root|
        seed(root)
        task_id = abandoned_task(root)

        exit_code, stdout, stderr = run(argv_for.call(task_id, root), cwd: root)

        expect(exit_code).not_to eq(0)
        expect(stdout).to eq('')
        body = JSON.parse(stderr)
        expect(body['ok']).to be(false)
        expect(body.dig('error', 'code')).to eq('task_terminal')
        expect(body.dig('error', 'details', 'task_id')).to eq(task_id)
      end
    end
  end

  describe 'owl next TASK-X' do
    it_behaves_like 'rejects an explicit terminal id',
                    ->(id, root) { ['next', id, '--root', root.to_s, '--json'] }
  end

  describe 'owl status TASK-X' do
    it_behaves_like 'rejects an explicit terminal id',
                    ->(id, root) { ['status', id, '--root', root.to_s, '--json'] }
  end

  describe 'owl task ready-steps TASK-X' do
    it_behaves_like 'rejects an explicit terminal id',
                    ->(id, root) { ['task', 'ready-steps', id, '--root', root.to_s, '--json'] }
  end

  describe 'owl instructions TASK-X' do
    it_behaves_like 'rejects an explicit terminal id',
                    ->(id, root) { ['instructions', id, '--root', root.to_s, '--json'] }
  end

  it 'does not reject an explicit LIVE task id' do
    with_tmp_project do |root|
      seed(root)
      run(['task', 'create', '--workflow', 'feature', '--title', 't', '--root', root.to_s, '--json'], cwd: root)

      exit_code, stdout, = run(['status', 'TASK-0001', '--root', root.to_s, '--json'], cwd: root)
      expect(exit_code).to eq(0)
      expect(JSON.parse(stdout)['task']['id']).to eq('TASK-0001')
    end
  end

  it 'owl next without an id falls through a terminal current pointer to no_available_task' do
    with_tmp_project do |root|
      seed(root)
      abandoned_task(root)
      # Re-point the (cleared-by-abandon) current pointer at the terminal task to
      # exercise the silent fallback rather than the explicit reject.
      run(['task', 'use', 'TASK-0001', '--root', root.to_s], cwd: root)

      exit_code, stdout, = run(['next', '--root', root.to_s, '--json'], cwd: root)
      expect(exit_code).to eq(0)
      body = JSON.parse(stdout)
      expect(body['ok']).to be(true)
      expect(body.dig('action', 'kind')).to eq('no_available_task')
    end
  end

  # Regression guard: in the seeded delivery workflows the `archive` step sets
  # the task status to `archived` BEFORE the terminal `commit_push` step runs, so
  # an `archived` task mid-flow must NOT be treated as terminal — `owl next` has
  # to keep dispatching `commit_push`.
  it 'still dispatches commit_push for an archived task whose workflow is mid-flow' do
    with_tmp_project do |root|
      task_id = archived_midflow_task(root)

      exit_code, stdout, = run(['next', task_id, '--root', root.to_s, '--json'], cwd: root)
      expect(exit_code).to eq(0)
      body = JSON.parse(stdout)
      expect(body.dig('action', 'kind')).to eq('dispatch_step')
      expect(body.dig('action', 'step_id')).to eq('commit_push')
    end
  end
end
