# frozen_string_literal: true

require 'json'
require 'stringio'
require 'yaml'

require 'owl/cli/api'

RSpec.describe 'owl workflow show diagram CLI' do
  def run(argv, cwd:)
    stdout = StringIO.new
    stderr = StringIO.new
    exit_code = Owl::Cli::Api.run(argv: argv, stdout: stdout, stderr: stderr, env: {}, cwd: cwd.to_s)
    [exit_code, stdout.string, stderr.string]
  end

  def init_project(root)
    run(['init', '--root', root.to_s], cwd: root)
  end

  def seed_feature(root)
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
        - id: specify
          skill: owl-step-run
          requires: [brief]
        - id: plan
          skill: owl-step-run
          requires: [specify]
      artifacts: []
    YAML
  end

  describe 'live mode (positional TASK-XXXX)' do
    it 'prints ASCII diagram with current step marker and progress' do
      with_tmp_project do |root|
        init_project(root)
        seed_feature(root)
        run(['task', 'create', '--workflow', 'feature', '--title', 'Test', '--root', root.to_s], cwd: root)
        run(['step', 'start', 'TASK-0001', 'brief', '--root', root.to_s], cwd: root)
        run(['step', 'complete', 'TASK-0001', 'brief', '--root', root.to_s], cwd: root)

        exit_code, stdout, _stderr = run(['workflow', 'show', 'TASK-0001', '--root', root.to_s], cwd: root)
        expect(exit_code).to eq(0)
        expect(stdout).to include('TASK-0001')
        expect(stdout).to include('workflow: feature')
        expect(stdout).to include('[✓] brief')
        expect(stdout).to include('[▶] specify')
        expect(stdout).to include('← current')
        expect(stdout).to include('Blockers: none')
      end
    end

    it 'returns structured live JSON with --json flag' do
      with_tmp_project do |root|
        init_project(root)
        seed_feature(root)
        run(['task', 'create', '--workflow', 'feature', '--title', 'T', '--root', root.to_s], cwd: root)

        exit_code, stdout, _stderr = run(['workflow', 'show', 'TASK-0001', '--json', '--root', root.to_s], cwd: root)
        expect(exit_code).to eq(0)
        body = JSON.parse(stdout)
        expect(body['ok']).to be(true)
        expect(body['mode']).to eq('live')
        expect(body.dig('task', 'id')).to eq('TASK-0001')
        expect(body.dig('task', 'workflow_key')).to eq('feature')
        expect(body['steps']).to be_an(Array)
        expect(body['steps'].first).to include('id', 'status', 'ready')
        expect(body['progress']).to include('done', 'total', 'pct')
        expect(body['blockers']).to eq([])
      end
    end

    it 'reports task_not_found for missing TASK-id' do
      with_tmp_project do |root|
        init_project(root)
        seed_feature(root)

        exit_code, _stdout, stderr = run(['workflow', 'show', 'TASK-9999', '--root', root.to_s], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).not_to be_nil
      end
    end
  end

  describe 'abstract mode (--workflow KEY)' do
    it 'prints ASCII diagram with workflow header and no progress' do
      with_tmp_project do |root|
        init_project(root)
        seed_feature(root)

        exit_code, stdout, _stderr = run(['workflow', 'show', '--workflow', 'feature', '--root', root.to_s], cwd: root)
        expect(exit_code).to eq(0)
        expect(stdout).to include('workflow: feature   (3 steps)')
        expect(stdout).to include('[ ] brief')
        expect(stdout).to include('[ ] specify')
        expect(stdout).to include('[ ] plan')
        expect(stdout).not_to include('Blockers')
        expect(stdout).not_to include('TASK-')
      end
    end

    it 'returns structured abstract JSON with --json flag' do
      with_tmp_project do |root|
        init_project(root)
        seed_feature(root)

        exit_code, stdout, _stderr = run(['workflow', 'show', '--workflow', 'feature', '--json', '--root', root.to_s],
                                         cwd: root)
        expect(exit_code).to eq(0)
        body = JSON.parse(stdout)
        expect(body['ok']).to be(true)
        expect(body['mode']).to eq('abstract')
        expect(body['workflow_key']).to eq('feature')
        expect(body['steps'].size).to eq(3)
      end
    end
  end

  describe 'legacy bare-key mode (backward compat)' do
    it 'returns legacy JSON definition payload by default' do
      with_tmp_project do |root|
        init_project(root)

        exit_code, stdout, _stderr = run(['workflow', 'show', 'feature', '--root', root.to_s], cwd: root)
        expect(exit_code).to eq(0)
        body = JSON.parse(stdout)
        expect(body['id']).to eq('feature')
        expect(body.dig('definition', 'steps')).to be_an(Array)
        expect(body['source_present']).to be(true)
      end
    end

    it 'returns unknown_workflow for an unregistered id' do
      with_tmp_project do |root|
        init_project(root)

        exit_code, _stdout, stderr = run(['workflow', 'show', 'nope', '--root', root.to_s], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('unknown_workflow')
      end
    end
  end

  describe 'invalid invocations' do
    it 'rejects passing both TASK-id positional and --workflow KEY' do
      with_tmp_project do |root|
        init_project(root)

        exit_code, _stdout, stderr = run(
          ['workflow', 'show', 'TASK-0001', '--workflow', 'feature', '--root', root.to_s], cwd: root
        )
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('invalid_arguments')
      end
    end

    it 'rejects empty invocation (no positional, no --workflow)' do
      with_tmp_project do |root|
        init_project(root)

        exit_code, _stdout, stderr = run(['workflow', 'show', '--root', root.to_s], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('invalid_arguments')
      end
    end
  end
end
