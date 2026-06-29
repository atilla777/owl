# frozen_string_literal: true

require 'json'
require 'stringio'

require 'owl/cli/api'
require 'owl/result'
require 'owl/tasks/api'

RSpec.describe Owl::Cli::Internal::Commands::Doctor do
  def cli(argv, root, stdout: StringIO.new, stderr: StringIO.new)
    code = Owl::Cli::Api.run(argv: argv, stdout: stdout, stderr: stderr, env: {}, cwd: root.to_s)
    [code, stdout.string, stderr.string]
  end

  def setup_drift(root)
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
    YAML
    cli(['task', 'create', '--workflow', 'quick', '--title', 't', '--root', root.to_s, '--json'], root)
    cli(['step', 'start', 'TASK-0001', 'build', '--root', root.to_s, '--json'], root)
    cli(['step', 'complete', 'TASK-0001', 'build', '--root', root.to_s, '--json'], root)
    # Completing the terminal step auto-promotes the task to `done` via
    # Steps::TaskFinalizer; reopen it to reproduce the drift `doctor` targets.
    cli(['task', 'set-status', 'TASK-0001', 'open', '--root', root.to_s, '--json'], root)
  end

  def status_of(root, task_id)
    code, out, = cli(['task', 'inspect', task_id, '--root', root.to_s, '--json'], root)
    raise "inspect failed: #{out}" unless code.zero?

    JSON.parse(out).dig('task', 'status')
  end

  it 'reports drift as JSON without mutating state (report-only default)' do
    with_tmp_project do |root|
      setup_drift(root)

      code, out, = cli(['doctor', '--root', root.to_s, '--json'], root)
      body = JSON.parse(out)

      expect(code).to eq(0)
      expect(body['ok']).to be(true)
      expect(body['drifted'].map { |d| d['task_id'] }).to eq(['TASK-0001'])
      expect(body['fixed']).to eq([])
      expect(status_of(root, 'TASK-0001')).to eq('open')
    end
  end

  it '--fix promotes drifted tasks to done and reports the fix' do
    with_tmp_project do |root|
      setup_drift(root)

      code, out, = cli(['doctor', '--fix', '--root', root.to_s, '--json'], root)
      body = JSON.parse(out)

      expect(code).to eq(0)
      expect(body['fixed']).to eq([{ 'task_id' => 'TASK-0001', 'from' => 'open', 'to' => 'done' }])
      expect(status_of(root, 'TASK-0001')).to eq('done')
    end
  end

  it '--fix is idempotent: a second run finds no drift' do
    with_tmp_project do |root|
      setup_drift(root)
      cli(['doctor', '--fix', '--root', root.to_s, '--json'], root)

      _code, out, = cli(['doctor', '--fix', '--root', root.to_s, '--json'], root)
      body = JSON.parse(out)

      expect(body['drifted']).to eq([])
      expect(body['fixed']).to eq([])
    end
  end

  it 'surfaces a set_status error during --fix' do
    with_tmp_project do |root|
      setup_drift(root)
      allow(Owl::Tasks::Api).to receive(:set_status).and_return(
        Owl::Result.err(code: :boom, message: 'nope', details: {})
      )

      code, _out, err = cli(['doctor', '--fix', '--root', root.to_s, '--json'], root)
      body = JSON.parse(err)

      expect(code).to eq(1)
      expect(body['ok']).to be(false)
      expect(body['error']['code']).to eq('boom')
    end
  end
end
