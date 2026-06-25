# frozen_string_literal: true

require 'json'
require 'stringio'
require 'yaml'

require 'owl/cli/api'

RSpec.describe 'owl step ... and owl task ready-steps CLI subcommands' do
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
      steps:
        - id: a
        - id: b
          requires: ["a"]
      artifacts: []
    YAML
    run(['task', 'create', '--workflow', 'feature', '--title', 't', '--root', root.to_s], cwd: root)
    'TASK-0001'
  end

  describe 'task ready-steps' do
    it 'prints the ready set as JSON' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        exit_code, stdout, _stderr = run(['task', 'ready-steps', task_id, '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).to eq(0)
        body = JSON.parse(stdout)
        expect(body['ok']).to be(true)
        expect(body['ready'].map { |s| s['id'] }).to eq(['a'])
      end
    end

    it 'fails with invalid_arguments when TASK-ID is missing' do
      with_tmp_project do |root|
        setup_project(root)
        exit_code, _stdout, stderr = run(['task', 'ready-steps', '--root', root.to_s], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('invalid_arguments')
      end
    end

    it 'fails with task_not_found when the task does not exist' do
      with_tmp_project do |root|
        setup_project(root)
        exit_code, _stdout, stderr = run(['task', 'ready-steps', 'TASK-9999', '--root', root.to_s], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('task_not_found')
      end
    end
  end

  describe 'step start / complete / skip' do
    it 'walks a linear workflow start → complete → next ready' do
      with_tmp_project do |root|
        task_id = setup_project(root)

        start_exit, start_stdout, = run(['step', 'start', task_id, 'a', '--root', root.to_s, '--json'], cwd: root)
        expect(start_exit).to eq(0)
        expect(JSON.parse(start_stdout).dig('step', 'status')).to eq('running')

        complete_args = ['step', 'complete', task_id, 'a', '--root', root.to_s, '--json']
        complete_exit, complete_stdout, = run(complete_args, cwd: root)
        expect(complete_exit).to eq(0)
        expect(JSON.parse(complete_stdout).dig('step', 'status')).to eq('done')

        _ready_exit, ready_stdout, = run(['task', 'ready-steps', task_id, '--root', root.to_s, '--json'], cwd: root)
        expect(JSON.parse(ready_stdout)['ready'].map { |s| s['id'] }).to eq(['b'])
      end
    end

    it 'returns step_not_ready exit 1 with structured error' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        exit_code, _stdout, stderr = run(['step', 'start', task_id, 'b', '--root', root.to_s], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('step_not_ready')
      end
    end

    it 'returns step_not_running for complete on a pending step' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        exit_code, _stdout, stderr = run(['step', 'complete', task_id, 'a', '--root', root.to_s], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('step_not_running')
      end
    end

    it 'blocks complete and keeps the step running when an output artifact is invalid' do
      with_tmp_project do |root|
        task_id = setup_project_with_output_artifact(root)
        run(['step', 'start', task_id, 'a', '--root', root.to_s, '--json'], cwd: root)
        exit_code, _stdout, stderr = run(['step', 'complete', task_id, 'a', '--root', root.to_s], cwd: root)
        expect(exit_code).to eq(1)
        body = JSON.parse(stderr)
        expect(body.dig('error', 'code')).to eq('step_outputs_invalid')

        _inspect_exit, inspect_stdout, = run(['task', 'inspect', task_id, '--root', root.to_s, '--json'], cwd: root)
        steps = JSON.parse(inspect_stdout).dig('task', 'steps')
        expect(steps.find { |s| s['id'] == 'a' }['status']).to eq('running')
      end
    end

    it 'completes a step with a valid output artifact' do
      with_tmp_project do |root|
        task_id = setup_project_with_output_artifact(root)
        write("#{root}/tasks/#{task_id}/notes.md", "## Summary\n")
        run(['step', 'start', task_id, 'a', '--root', root.to_s, '--json'], cwd: root)
        exit_code, stdout, = run(['step', 'complete', task_id, 'a', '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).to eq(0)
        expect(JSON.parse(stdout).dig('step', 'status')).to eq('done')
      end
    end

    def setup_project_with_output_artifact(root)
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
        artifacts:
          notes:
            type: notes
            storage:
              role: tasks
              path: "{{task.id}}/notes.md"
        steps:
          - id: a
            creates: [notes]
      YAML
      write("#{root}/.owl/artifacts.yaml", <<~YAML)
        schema_version: 1
        artifacts:
          notes:
            source: "artifacts/notes/artifact.yaml"
      YAML
      write("#{root}/.owl/artifacts/notes/artifact.yaml", <<~YAML)
        id: notes
        kind: markdown
        validation:
          required_sections:
            - Summary
      YAML
      run(['task', 'create', '--workflow', 'feature', '--title', 't', '--root', root.to_s], cwd: root)
      'TASK-0001'
    end

    it 'records skip_reason and returns ok' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        skip_args = ['step', 'skip', task_id, 'a', '--reason', 'unused', '--root', root.to_s, '--json']
        exit_code, stdout, = run(skip_args, cwd: root)
        expect(exit_code).to eq(0)
        body = JSON.parse(stdout)
        expect(body.dig('step', 'status')).to eq('skipped')
        expect(body.dig('step', 'skip_reason')).to eq('unused')
      end
    end

    it 'returns missing_reason when --reason is omitted' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        exit_code, _stdout, stderr = run(['step', 'skip', task_id, 'a', '--root', root.to_s], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('missing_reason')
      end
    end

    it 'returns invalid_arguments when STEP-ID is missing' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        exit_code, _stdout, stderr = run(['step', 'start', task_id, '--root', root.to_s], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('invalid_arguments')
      end
    end
  end

  describe 'per-task active-step locking (Phase 2)' do
    it 'lets two different tasks each hold a running step at the same time' do
      with_tmp_project do |root|
        setup_project(root) # TASK-0001
        run(['task', 'create', '--workflow', 'feature', '--title', 't2', '--root', root.to_s], cwd: root)

        e1, = run(['step', 'start', 'TASK-0001', 'a', '--root', root.to_s, '--json'], cwd: root)
        e2, out2, = run(['step', 'start', 'TASK-0002', 'a', '--root', root.to_s, '--json'], cwd: root)
        expect(e1).to eq(0)
        expect(e2).to eq(0)
        expect(JSON.parse(out2).dig('step', 'status')).to eq('running')

        # Both per-task locks coexist.
        expect(Pathname.new("#{root}/.owl/local/active_steps/TASK-0001.yaml")).to exist
        expect(Pathname.new("#{root}/.owl/local/active_steps/TASK-0002.yaml")).to exist
      end
    end

    it 'blocks a second running step on the same task with active_step_locked' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        run(['step', 'start', task_id, 'a', '--root', root.to_s, '--json'], cwd: root)
        exit_code, _stdout, stderr = run(['step', 'start', task_id, 'b', '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).to eq(2)
        error = JSON.parse(stderr)['error']
        expect(error['code']).to eq('active_step_locked')
        expect(error['details']['locked_step_id']).to eq('a')
      end
    end

    it 'reset releases the active-step lock so the task is free again' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        lock = Pathname.new("#{root}/.owl/local/active_steps/#{task_id}.yaml")
        run(['step', 'start', task_id, 'a', '--root', root.to_s, '--json'], cwd: root)
        expect(lock).to exist

        reset_code, = run(['step', 'reset', task_id, 'a', '--root', root.to_s, '--json'], cwd: root)
        expect(reset_code).to eq(0)
        expect(lock).not_to exist

        # The task is no longer wedged: a fresh `step start` succeeds.
        start_code, out, = run(['step', 'start', task_id, 'a', '--root', root.to_s, '--json'], cwd: root)
        expect(start_code).to eq(0)
        expect(JSON.parse(out).dig('step', 'status')).to eq('running')
      end
    end

    it 'reset succeeds when no active-step lock is present (no-op clear)' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        lock = Pathname.new("#{root}/.owl/local/active_steps/#{task_id}.yaml")
        run(['step', 'start', task_id, 'a', '--root', root.to_s, '--json'], cwd: root)
        lock.delete # simulate a lock-less running step

        reset_code, = run(['step', 'reset', task_id, 'a', '--root', root.to_s, '--json'], cwd: root)
        expect(reset_code).to eq(0)
        expect(lock).not_to exist
      end
    end

    it 'reset leaves a lock that refers to a different step untouched' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        lock = Pathname.new("#{root}/.owl/local/active_steps/#{task_id}.yaml")
        run(['step', 'start', task_id, 'a', '--root', root.to_s, '--json'], cwd: root)
        # Simulate a drifted lock that points at a different step.
        write(lock.to_s, <<~YAML)
          ---
          schema_version: 1
          task_id: #{task_id}
          step_id: b
          session_type: execution
          declared_at: '2026-06-25T00:00:00Z'
        YAML

        reset_code, = run(['step', 'reset', task_id, 'a', '--root', root.to_s, '--json'], cwd: root)
        expect(reset_code).to eq(0)
        expect(lock).to exist
        expect(YAML.safe_load(lock.read)['step_id']).to eq('b')
      end
    end
  end

  describe 'unknown step subcommand' do
    it 'reports unknown_command' do
      with_tmp_project do |root|
        setup_project(root)
        exit_code, _stdout, stderr = run(['step', 'nope', '--root', root.to_s], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('unknown_command')
      end
    end

    it 'reports unknown_command for bare step' do
      with_tmp_project do |root|
        setup_project(root)
        exit_code, _stdout, stderr = run(['step', '--root', root.to_s], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('unknown_command')
      end
    end
  end

  describe 'step variants' do
    def setup_variant_project(root)
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
        steps:
          - id: brief
            skill: owl-step-run
            default_variant: feature
            variants:
              feature:
                context_file: brief.feature.context.md
              root_cause:
                context_file: brief.root_cause.context.md
          - id: implement
            skill: owl-step-run
            requires: [brief]
        artifacts:
          brief:
            type: brief
            storage:
              role: tasks
              path: "{{task.id}}/brief.md"
      YAML
      write("#{root}/.owl/workflows/feature/brief.feature.context.md", "# Purpose\nfeature default\n")
      write("#{root}/.owl/workflows/feature/brief.root_cause.context.md", "# Purpose\nroot cause\n")
    end

    it 'task create --variant persists step_variants on the task' do
      with_tmp_project do |root|
        setup_variant_project(root)
        exit_code, stdout, = run(
          ['task', 'create', '--workflow', 'feature', '--title', 'fix it',
           '--variant', 'brief=root_cause', '--root', root.to_s, '--json'],
          cwd: root
        )
        expect(exit_code).to eq(0)
        task = JSON.parse(stdout)['task']
        expect(task['step_variants']).to eq('brief' => 'root_cause')
      end
    end

    it 'task create --variant rejects unknown variant name' do
      with_tmp_project do |root|
        setup_variant_project(root)
        exit_code, _stdout, stderr = run(
          ['task', 'create', '--workflow', 'feature', '--title', 't',
           '--variant', 'brief=ghost', '--root', root.to_s, '--json'],
          cwd: root
        )
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('unknown_step_variant')
      end
    end

    it 'step start --variant writes the variant to task.yaml before flipping status' do
      with_tmp_project do |root|
        setup_variant_project(root)
        run(['task', 'create', '--workflow', 'feature', '--title', 't', '--root', root.to_s], cwd: root)
        exit_code, = run(
          ['step', 'start', 'TASK-0001', 'brief', '--variant', 'root_cause', '--root', root.to_s, '--json'],
          cwd: root
        )
        expect(exit_code).to eq(0)
        task_yaml = YAML.safe_load(Pathname.new("#{root}/tasks/TASK-0001/task.yaml").read)
        expect(task_yaml['step_variants']).to eq('brief' => 'root_cause')
      end
    end

    it 'step show returns chosen variant and its context body' do
      with_tmp_project do |root|
        setup_variant_project(root)
        run(['task', 'create', '--workflow', 'feature', '--title', 't',
             '--variant', 'brief=root_cause', '--root', root.to_s], cwd: root)
        exit_code, stdout, = run(['step', 'show', 'TASK-0001', 'brief', '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).to eq(0)
        bundle = JSON.parse(stdout)['bundle']
        expect(bundle.dig('step', 'variant')).to eq('root_cause')
        expect(bundle['context']).to include('root cause')
      end
    end

    it 'step show falls back to default_variant when none is chosen' do
      with_tmp_project do |root|
        setup_variant_project(root)
        run(['task', 'create', '--workflow', 'feature', '--title', 't', '--root', root.to_s], cwd: root)
        _, stdout, = run(['step', 'show', 'TASK-0001', 'brief', '--root', root.to_s, '--json'], cwd: root)
        bundle = JSON.parse(stdout)['bundle']
        expect(bundle.dig('step', 'variant')).to eq('feature')
        expect(bundle['context']).to include('feature default')
      end
    end

    it 'step show overlays include variant-specific docs/ai/<step>/<variant>.md' do
      with_tmp_project do |root|
        setup_variant_project(root)
        Pathname.new("#{root}/docs/ai/brief").mkpath
        File.write("#{root}/docs/ai/brief/root_cause.md", "# Root-cause rules\n")
        run(['task', 'create', '--workflow', 'feature', '--title', 't',
             '--variant', 'brief=root_cause', '--root', root.to_s], cwd: root)
        _, stdout, = run(['step', 'show', 'TASK-0001', 'brief', '--root', root.to_s, '--json'], cwd: root)
        bundle = JSON.parse(stdout)['bundle']
        sources = bundle['overlays'].map { |o| o['source'] }
        expect(sources).to include(a_string_matching(%r{docs/ai/brief/root_cause\.md\z}))
      end
    end
  end
end
