# frozen_string_literal: true

require 'json'
require 'stringio'
require 'yaml'

require 'owl/cli/api'

RSpec.describe 'owl next CLI subcommand' do
  def run(argv, cwd:)
    stdout = StringIO.new
    stderr = StringIO.new
    exit_code = Owl::Cli::Api.run(argv: argv, stdout: stdout, stderr: stderr, env: {}, cwd: cwd.to_s)
    [exit_code, stdout.string, stderr.string]
  end

  def init_project(root)
    run(['init', '--root', root.to_s], cwd: root)
  end

  def seed_two_step_feature(root)
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
          skill: owl-step-execution
          session_type: execution
          requires: ["a"]
      artifacts: []
    YAML
  end

  def seed_single_step(root)
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
  end

  def seed_gated_composite(root)
    write("#{root}/.owl/workflows.yaml", <<~YAML)
      schema_version: 1
      workflows:
        comp:
          enabled: true
          source: "workflows/comp/workflow.yaml"
    YAML
    write("#{root}/.owl/workflows/comp/workflow.yaml", <<~YAML)
      id: comp
      kind: composite_task
      steps:
        - id: decompose
          skill: owl-step-discussion
          session_type: discussion
        - id: finalize
          skill: owl-step-discussion
          session_type: discussion
          requires: ["decompose"]
          gate: children_complete
      artifacts: []
    YAML
  end

  describe 'task resolution ladder' do
    it 'auto-selects the top runnable task as a dispatch_step (source auto_select, no mutation)' do # rubocop:disable RSpec/MultipleExpectations
      with_tmp_project do |root|
        init_project(root)
        seed_two_step_feature(root)
        run(['task', 'create', '--workflow', 'feature', '--title', 't', '--root', root.to_s], cwd: root)

        exit_code, stdout, _stderr = run(['next', '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).to eq(0)
        body = JSON.parse(stdout)
        expect(body['ok']).to be(true)
        expect(body.dig('action', 'kind')).to eq('dispatch_step')
        expect(body.dig('action', 'task_id')).to eq('TASK-0001')
        expect(body.dig('action', 'step_id')).to eq('a')
        expect(body.dig('action', 'session_type')).to eq('discussion')
        expect(body.dig('action', 'skill')).to eq('owl-step-discussion')
        expect(body.dig('task_resolution', 'source')).to eq('auto_select')
        expect(body.dig('task_resolution', 'reason')).to be_a(String)

        # read-only: no current pointer was written and no claim was taken
        current_exit, = run(['task', 'current', '--root', root.to_s, '--json'], cwd: root)
        expect(current_exit).not_to eq(0)
        _, claims_out, = run(['task', 'claims', '--root', root.to_s, '--json'], cwd: root)
        expect(JSON.parse(claims_out)['claims']).to eq([])
      end
    end

    it 'honours an explicit TASK-ID over the current pointer (source explicit)' do
      with_tmp_project do |root|
        init_project(root)
        seed_two_step_feature(root)
        run(['task', 'create', '--workflow', 'feature', '--title', 'one', '--root', root.to_s], cwd: root)
        run(['task', 'create', '--workflow', 'feature', '--title', 'two', '--root', root.to_s], cwd: root)
        run(['task', 'use', 'TASK-0001', '--root', root.to_s], cwd: root)

        exit_code, stdout, _stderr = run(['next', 'TASK-0002', '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).to eq(0)
        body = JSON.parse(stdout)
        expect(body.dig('action', 'task_id')).to eq('TASK-0002')
        expect(body.dig('task_resolution', 'source')).to eq('explicit')
      end
    end

    it 'resolves from the current pointer when no positional id is given' do
      with_tmp_project do |root|
        init_project(root)
        seed_two_step_feature(root)
        run(['task', 'create', '--workflow', 'feature', '--title', 't', '--root', root.to_s], cwd: root)
        run(['task', 'use', 'TASK-0001', '--root', root.to_s], cwd: root)

        _exit, stdout, = run(['next', '--root', root.to_s, '--json'], cwd: root)
        body = JSON.parse(stdout)
        expect(body.dig('task_resolution', 'source')).to eq('current_pointer')
        expect(body.dig('action', 'kind')).to eq('dispatch_step')
      end
    end
  end

  describe 'idempotence / read-only contract' do
    it 'returns identical results on two consecutive calls and mutates nothing' do
      with_tmp_project do |root|
        init_project(root)
        seed_two_step_feature(root)
        run(['task', 'create', '--workflow', 'feature', '--title', 't', '--root', root.to_s], cwd: root)

        _e1, out1, = run(['next', '--root', root.to_s, '--json'], cwd: root)
        _e2, out2, = run(['next', '--root', root.to_s, '--json'], cwd: root)
        expect(JSON.parse(out1)).to eq(JSON.parse(out2))

        _, claims_out, = run(['task', 'claims', '--root', root.to_s, '--json'], cwd: root)
        expect(JSON.parse(claims_out)['claims']).to eq([])
      end
    end
  end

  describe 'terminal outcomes (all exit 0)' do
    it 'returns no_available_task when nothing is runnable' do
      with_tmp_project do |root|
        init_project(root)
        seed_two_step_feature(root)

        exit_code, stdout, _stderr = run(['next', '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).to eq(0)
        body = JSON.parse(stdout)
        expect(body.dig('action', 'kind')).to eq('no_available_task')
        expect(body.dig('task_resolution', 'source')).to eq('none')
      end
    end

    it 'returns done when the terminal step is complete' do
      with_tmp_project do |root|
        init_project(root)
        seed_single_step(root)
        run(['task', 'create', '--workflow', 'tiny', '--title', 't', '--root', root.to_s], cwd: root)
        run(['step', 'start', 'TASK-0001', 'only', '--root', root.to_s], cwd: root)
        run(['step', 'complete', 'TASK-0001', 'only', '--root', root.to_s], cwd: root)

        exit_code, stdout, _stderr = run(['next', 'TASK-0001', '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).to eq(0)
        body = JSON.parse(stdout)
        expect(body.dig('action', 'kind')).to eq('done')
        expect(body.dig('action', 'task_id')).to eq('TASK-0001')
      end
    end

    it 'returns stop_blocked when the graph is blocked by an in-flight step' do
      with_tmp_project do |root|
        init_project(root)
        seed_two_step_feature(root)
        run(['task', 'create', '--workflow', 'feature', '--title', 't', '--root', root.to_s], cwd: root)
        run(['step', 'start', 'TASK-0001', 'a', '--root', root.to_s], cwd: root)

        exit_code, stdout, _stderr = run(['next', 'TASK-0001', '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).to eq(0)
        body = JSON.parse(stdout)
        expect(body.dig('action', 'kind')).to eq('stop_blocked')
        expect(body.dig('action', 'blocker')).to include('running')
        expect(body.dig('task_resolution', 'needs_adopt')).to be(false)
      end
    end

    it 'returns handoff_composite when a composite parent waits on its children' do
      with_tmp_project do |root|
        init_project(root)
        seed_gated_composite(root)
        run(['task', 'create', '--workflow', 'comp', '--title', 'parent', '--root', root.to_s], cwd: root)
        run(['step', 'start', 'TASK-0001', 'decompose', '--root', root.to_s], cwd: root)
        run(['step', 'complete', 'TASK-0001', 'decompose', '--root', root.to_s], cwd: root)

        exit_code, stdout, _stderr = run(['next', 'TASK-0001', '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).to eq(0)
        body = JSON.parse(stdout)
        expect(body.dig('action', 'kind')).to eq('handoff_composite')
        expect(body.dig('action', 'children')).to be_a(Hash)
        expect(body.dig('action', 'children', 'aggregate')).to be_a(String)
      end
    end
  end

  describe 'needs_adopt edge case' do
    it 'flags needs_adopt when a stuck running step carries an expired lease' do
      with_tmp_project do |root|
        init_project(root)
        seed_two_step_feature(root)
        run(['task', 'create', '--workflow', 'feature', '--title', 't', '--root', root.to_s], cwd: root)
        run(['step', 'start', 'TASK-0001', 'a', '--root', root.to_s], cwd: root)
        # Simulate a dead session: a lease that has already expired.
        write("#{root}/.owl/local/claims/TASK-0001.yaml", <<~YAML)
          task_id: "TASK-0001"
          claimed_by: "dead-session"
          expires_at: "2000-01-01T00:00:00Z"
        YAML

        exit_code, stdout, _stderr = run(['next', 'TASK-0001', '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).to eq(0)
        body = JSON.parse(stdout)
        expect(body.dig('action', 'kind')).to eq('stop_blocked')
        expect(body.dig('task_resolution', 'needs_adopt')).to be(true)
      end
    end
  end

  describe 'variant resolution on dispatch_step' do
    def seed_variant_feature(root)
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
            skill: owl-step-discussion
            session_type: discussion
            default_variant: feature
            variants:
              feature:
                context_file: brief.feature.context.md
              root_cause:
                context_file: brief.root_cause.context.md
        artifacts: []
      YAML
      write("#{root}/.owl/workflows/feature/brief.feature.context.md", "# Purpose\nfeature default\n")
      write("#{root}/.owl/workflows/feature/brief.root_cause.context.md", "# Purpose\nroot cause\n")
    end

    it 'reports the default_variant when the task chose none' do
      with_tmp_project do |root|
        init_project(root)
        seed_variant_feature(root)
        run(['task', 'create', '--workflow', 'feature', '--title', 't', '--root', root.to_s], cwd: root)

        _exit, stdout, = run(['next', '--root', root.to_s, '--json'], cwd: root)
        body = JSON.parse(stdout)
        expect(body.dig('action', 'kind')).to eq('dispatch_step')
        expect(body.dig('action', 'variant')).to eq('feature')
      end
    end

    it 'reports the task-chosen variant over the default' do
      with_tmp_project do |root|
        init_project(root)
        seed_variant_feature(root)
        run(['task', 'create', '--workflow', 'feature', '--title', 't',
             '--variant', 'brief=root_cause', '--root', root.to_s], cwd: root)

        _exit, stdout, = run(['next', '--root', root.to_s, '--json'], cwd: root)
        body = JSON.parse(stdout)
        expect(body.dig('action', 'variant')).to eq('root_cause')
      end
    end
  end
end
