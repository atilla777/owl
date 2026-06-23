# frozen_string_literal: true

require 'json'
require 'stringio'

require 'owl/cli/api'
require 'owl/verification/api'
require 'owl/verification/internal/command_runner'
require 'owl/verification/internal/engine'

# Drives the REAL `Owl::Verification::Api.run` engine against a seeded feature
# task, with an injected runner so no real suite is executed. Asserts that Owl
# (not the agent) authors the status from the command's exit code and rewrites
# the verification artifact.
RSpec.describe Owl::Verification::Api do
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

  def fake_runner(exit_code:, stdout: '', stderr: '', timed_out: false, duration: 0.1)
    runner = Object.new
    outcome = Owl::Verification::Internal::CommandRunner::Outcome.new(
      exit_code: exit_code, stdout: stdout, stderr: stderr, timed_out: timed_out, duration: duration
    )
    runner.define_singleton_method(:run) { |**| outcome }
    runner
  end

  def verification_doc(root, task_id)
    (root + "tasks/#{task_id}/verification.md").read
  end

  describe '.run' do
    it 'authors status: passed when the command exits zero and records the run' do
      with_tmp_project do |root|
        task_id = setup_task(root)
        result = described_class.run(
          root: root, task_id: task_id, command: 'bundle exec rspec',
          runner: fake_runner(exit_code: 0, stdout: "42 examples, 0 failures\n")
        )

        expect(result).to be_ok
        expect(result.value[:status]).to eq('passed')
        expect(result.value[:exit_code]).to eq(0)
        expect(result.value[:command]).to eq('bundle exec rspec')

        doc = verification_doc(root, task_id)
        expect(doc).to match(/^status: passed$/)
        expect(doc).to include('bundle exec rspec')
        expect(doc).to include('42 examples, 0 failures')
      end
    end

    it 'authors status: failed when the command exits non-zero (agent cannot override)' do
      with_tmp_project do |root|
        task_id = setup_task(root)
        result = described_class.run(
          root: root, task_id: task_id, command: 'bundle exec rspec',
          runner: fake_runner(exit_code: 1, stderr: "1 example, 1 failure\n")
        )

        expect(result).to be_ok
        expect(result.value[:status]).to eq('failed')
        expect(result.value[:exit_code]).to eq(1)
        expect(verification_doc(root, task_id)).to match(/^status: failed$/)
      end
    end

    it 'authors status: failed with a timeout reason when the run times out' do
      with_tmp_project do |root|
        task_id = setup_task(root)
        result = described_class.run(
          root: root, task_id: task_id, command: 'sleep 999',
          runner: fake_runner(exit_code: nil, timed_out: true)
        )

        expect(result).to be_ok
        expect(result.value[:status]).to eq('failed')
        expect(result.value[:timed_out]).to be(true)
        expect(verification_doc(root, task_id)).to include('partial_reason: timeout')
      end
    end

    it 'errs when no command is configured and none is supplied' do
      with_tmp_project do |root|
        task_id = setup_task(root)
        result = described_class.run(root: root, task_id: task_id, runner: fake_runner(exit_code: 0))
        expect(result).to be_err
        expect(result.code).to eq(:verification_command_missing)
      end
    end

    it 'reads the command from settings.verification.command when not supplied' do
      with_tmp_project do |root|
        task_id = setup_task(root)
        set_cmd(root, 'echo hi')

        result = described_class.run(root: root, task_id: task_id, runner: fake_runner(exit_code: 0))
        expect(result).to be_ok
        expect(result.value[:command]).to eq('echo hi')
      end
    end
  end

  describe '.configured_command' do
    it 'returns nil when unset and the trimmed command when set' do
      with_tmp_project do |root|
        setup_task(root)
        expect(described_class.configured_command(root: root)).to be_nil
        set_cmd(root, 'bundle exec rspec')
        expect(described_class.configured_command(root: root)).to eq('bundle exec rspec')
      end
    end
  end

  describe '.gate' do
    it 'is not applicable to a step without verify: true' do
      with_tmp_project do |root|
        task_id = setup_task(root)
        result = described_class.gate(root: root, task_id: task_id, step_id: 'implement')
        expect(result).to be_ok
        expect(result.value[:applicable]).to be(false)
      end
    end

    it 'is fail-open (inactive + warning) on a verify step with no command' do
      with_tmp_project do |root|
        task_id = setup_task(root)
        result = described_class.gate(root: root, task_id: task_id, step_id: 'review_code')
        expect(result).to be_ok
        expect(result.value[:gate_active]).to be(false)
        expect(result.value.dig(:warning, :code)).to eq(:verification_gate_inactive)
      end
    end

    it 'passes a verify step when the command exits zero' do
      with_tmp_project do |root|
        task_id = setup_task(root)
        set_cmd(root, 'bundle exec rspec')
        result = described_class.gate(
          root: root, task_id: task_id, step_id: 'review_code', runner: fake_runner(exit_code: 0)
        )
        expect(result).to be_ok
        expect(result.value[:gate_active]).to be(true)
        expect(result.value[:status]).to eq('passed')
      end
    end

    it 'blocks a verify step when the command fails' do
      with_tmp_project do |root|
        task_id = setup_task(root)
        set_cmd(root, 'bundle exec rspec')
        result = described_class.gate(
          root: root, task_id: task_id, step_id: 'review_code', runner: fake_runner(exit_code: 2)
        )
        expect(result).to be_err
        expect(result.code).to eq(:verification_failed)
        expect(result.details[:status]).to eq('failed')
      end
    end

    it 'does not block on a partial objective status (warning only)' do
      with_tmp_project do |root|
        task_id = setup_task(root)
        set_cmd(root, 'bundle exec rspec')
        allow(Owl::Verification::Internal::Engine).to receive(:run).and_return(
          Owl::Result.ok(status: 'partial', exit_code: 3, command: 'bundle exec rspec',
                         output_tail: '', duration: 0.1, timed_out: false)
        )
        result = described_class.gate(root: root, task_id: task_id, step_id: 'review_code')
        expect(result).to be_ok
        expect(result.value[:status]).to eq('partial')
        expect(result.value.dig(:warning, :code)).to eq(:verification_partial)
      end
    end

    it 'propagates an engine error (e.g. command missing) unchanged' do
      with_tmp_project do |root|
        task_id = setup_task(root)
        set_cmd(root, 'bundle exec rspec')
        allow(Owl::Verification::Internal::Engine).to receive(:run).and_return(
          Owl::Result.err(code: :verification_command_missing, message: 'x')
        )
        result = described_class.gate(root: root, task_id: task_id, step_id: 'review_code')
        expect(result).to be_err
        expect(result.code).to eq(:verification_command_missing)
      end
    end
  end
end
