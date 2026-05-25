# frozen_string_literal: true

require 'json'
require 'stringio'
require 'yaml'

require 'owl/cli/api'

RSpec.describe 'owl step ... CLI fallback (KOS-159: lock + current.yaml)' do
  def run(argv, cwd:, stdin: nil)
    stdout = StringIO.new
    stderr = StringIO.new
    original_stdin = $stdin
    $stdin = stdin if stdin
    begin
      exit_code = Owl::Cli::Api.run(
        argv: argv, stdout: stdout, stderr: stderr,
        env: {}, cwd: cwd.to_s
      )
    ensure
      $stdin = original_stdin
    end
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

  describe 'step start' do
    it 'rejects missing step_id even when current.yaml is set (start has no inference)' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        run(['task', 'use', task_id, '--root', root.to_s], cwd: root)

        exit_code, _stdout, stderr = run(['step', 'start', '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('invalid_arguments')
      end
    end
  end

  describe 'step complete' do
    it 'resolves both ids from active_step.yaml lock when neither flag is passed' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        run(['step', 'start', task_id, 'a', '--root', root.to_s], cwd: root)

        # No positional args — fallback to lock for both task_id and step_id.
        exit_code, stdout, = run(['step', 'complete', '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).to eq(0)
        body = JSON.parse(stdout)
        expect(body['resolved_task_id_source']).to eq('active_step_lock')
        expect(body['resolved_step_id_source']).to eq('active_step_lock')
        expect(body.dig('step', 'status')).to eq('done')
      end
    end

    it 'infers running step_id from index when lock is absent but current.yaml is set' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        run(['step', 'start', task_id, 'a', '--root', root.to_s], cwd: root)

        File.delete("#{root}/.owl/local/active_step.yaml")
        run(['task', 'use', task_id, '--root', root.to_s], cwd: root)

        exit_code, stdout, = run(['step', 'complete', '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).to eq(0)
        body = JSON.parse(stdout)
        expect(body['resolved_task_id_source']).to eq('current_pointer')
        expect(body['resolved_step_id_source']).to eq('running_step_inference')
      end
    end

    it 'returns ambiguous_step with exit 2 when no step is running' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        run(['task', 'use', task_id, '--root', root.to_s], cwd: root)

        exit_code, _stdout, stderr = run(['step', 'complete', '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).to eq(2)
        error = JSON.parse(stderr)['error']
        expect(error['code']).to eq('ambiguous_step')
        expect(error['error_class']).to eq('recoverable')
        expect(error['details']['running_step_ids']).to eq([])
      end
    end
  end

  describe 'step report' do
    let(:valid_report) do
      <<~MD
        ---
        status: completed
        summary: "Test report"
        session_type: execution
        ---
        ## Summary
        body
      MD
    end

    it 'falls back to lock for both ids in write mode' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        run(['step', 'start', task_id, 'a', '--root', root.to_s], cwd: root)

        exit_code, stdout, = run(
          ['step', 'report', '--body', '-', '--root', root.to_s, '--json'],
          cwd: root, stdin: StringIO.new(valid_report)
        )
        expect(exit_code).to eq(0)
        body = JSON.parse(stdout)
        expect(body['resolved_task_id_source']).to eq('active_step_lock')
        expect(body['resolved_step_id_source']).to eq('active_step_lock')
        expect(body['task_id']).to eq(task_id)
        expect(body['step_id']).to eq('a')
      end
    end
  end

  describe 'invalid state fail-fast' do
    it 'returns active_step_lock_invalid without falling back to current.yaml' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        run(['task', 'use', task_id, '--root', root.to_s], cwd: root)
        write("#{root}/.owl/local/active_step.yaml", 'not: [a yaml: mapping}')

        exit_code, _stdout, stderr = run(['step', 'complete', '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('active_step_lock_invalid')
      end
    end
  end
end
