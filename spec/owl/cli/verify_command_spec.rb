# frozen_string_literal: true

require 'json'
require 'stringio'

require 'owl/cli/api'

# Direct specs for the `owl verify TASK-ID` CLI command across all of its
# branches, driven through the real `Owl::Cli::Api.run` with StringIO (as in
# run_command_spec). The configured commands are real shell builtins so the
# objective run is genuine but instant. Unix-only.
RSpec.describe 'owl verify (CLI)' do
  def cli(argv, root)
    out = StringIO.new
    err = StringIO.new
    code = Owl::Cli::Api.run(argv: argv, stdout: out, stderr: err, env: {}, cwd: root.to_s)
    [code, out.string, err.string]
  end

  def setup_task(root)
    cli(['init', '--root', root.to_s], root)
    _, stdout, = cli(
      ['task', 'create', '--workflow', 'feature', '--title', 'v', '--root', root.to_s, '--json'], root
    )
    JSON.parse(stdout).dig('task', 'id')
  end

  def set_cmd(root, command)
    cli(['config', 'set', 'settings.verification.command', command, '--root', root.to_s, '--json'], root)
  end

  it 'fails with invalid_arguments when no TASK-ID is given' do
    with_tmp_project do |root|
      setup_task(root)
      code, _out, err = cli(['verify', '--root', root.to_s, '--json'], root)

      expect(code).not_to eq(0)
      body = JSON.parse(err)
      expect(body['ok']).to be(false)
      expect(body.dig('error', 'code')).to eq('invalid_arguments')
    end
  end

  it 'is fail-open (gate_active:false + warning) when no command is configured' do
    with_tmp_project do |root|
      task_id = setup_task(root)
      code, out, err = cli(['verify', task_id, '--root', root.to_s, '--json'], root)

      expect(code).to eq(0)
      body = JSON.parse(out)
      expect(body['ok']).to be(true)
      expect(body['gate_active']).to be(false)
      expect(err).to include('verification_gate_inactive')
    end
  end

  it 'runs the command and reports status passed with exit_code and command when it succeeds' do
    with_tmp_project do |root|
      task_id = setup_task(root)
      set_cmd(root, "sh -c 'exit 0'")

      code, out, = cli(['verify', task_id, '--root', root.to_s, '--json'], root)

      expect(code).to eq(0)
      body = JSON.parse(out)
      expect(body['ok']).to be(true)
      expect(body['gate_active']).to be(true)
      expect(body['status']).to eq('passed')
      expect(body['exit_code']).to eq(0)
      expect(body['command']).to eq("sh -c 'exit 0'")
    end
  end

  it 'reports status failed without crashing when the command exits non-zero' do
    with_tmp_project do |root|
      task_id = setup_task(root)
      set_cmd(root, "sh -c 'exit 1'")

      code, out, = cli(['verify', task_id, '--root', root.to_s, '--json'], root)

      expect(code).to eq(0)
      body = JSON.parse(out)
      expect(body['ok']).to be(true)
      expect(body['gate_active']).to be(true)
      expect(body['status']).to eq('failed')
      expect(body['exit_code']).to eq(1)
    end
  end

  it 'propagates a structured engine error for an unknown task id' do
    with_tmp_project do |root|
      setup_task(root)
      set_cmd(root, "sh -c 'exit 0'")

      code, _out, err = cli(['verify', 'TASK-9999', '--root', root.to_s, '--json'], root)

      expect(code).not_to eq(0)
      body = JSON.parse(err)
      expect(body['ok']).to be(false)
      expect(body['error']).to be_a(Hash)
      expect(body.dig('error', 'code')).to be_a(String)
    end
  end
end
