# frozen_string_literal: true

require 'owl/verification/internal/command_runner'

# Exercises the REAL subprocess layer (no Open3 stubbing): exit codes, output
# capture, timeout → TERM of the whole process group, and spawn failure. This
# is the most failure-critical layer of the objective verification gate, and
# the engine specs inject a fake runner, so it is otherwise unpatched.
#
# Unix-only: relies on `pgroup: true` + `Process.kill('TERM', -pid)` semantics.
RSpec.describe Owl::Verification::Internal::CommandRunner do
  # Poll until `pid` is gone (raises Errno::ESRCH), up to `deadline` seconds.
  def wait_dead(pid, deadline: 3.0)
    stop = Process.clock_gettime(Process::CLOCK_MONOTONIC) + deadline
    loop do
      Process.kill(0, pid)
      return false if Process.clock_gettime(Process::CLOCK_MONOTONIC) > stop

      sleep 0.02
    end
  rescue Errno::ESRCH
    true
  end

  describe '.run exit codes' do
    it 'propagates a zero exit code with timed_out false' do
      outcome = described_class.run(command: "sh -c 'exit 0'", chdir: Dir.pwd, timeout: 5)

      expect(outcome.exit_code).to eq(0)
      expect(outcome.timed_out).to be(false)
    end

    it 'propagates a non-zero exit code verbatim' do
      outcome = described_class.run(command: "sh -c 'exit 3'", chdir: Dir.pwd, timeout: 5)

      expect(outcome.exit_code).to eq(3)
      expect(outcome.timed_out).to be(false)
    end
  end

  describe '.run output capture' do
    it 'captures stdout and stderr separately' do
      outcome = described_class.run(command: "sh -c 'echo out; echo err 1>&2'", chdir: Dir.pwd, timeout: 5)

      expect(outcome.exit_code).to eq(0)
      expect(outcome.stdout).to include('out')
      expect(outcome.stderr).to include('err')
    end
  end

  describe '.run timeout' do
    it 'flags timed_out, returns a nil exit code, and kills the runaway process group' do
      Dir.mktmpdir('owl-runner-') do |dir|
        pid_file = File.join(dir, 'child.pid')
        # The shell records its own PID (the process-group leader) then sleeps
        # far longer than the timeout, so a clean run would never finish first.
        command = "sh -c 'echo $$ > #{pid_file}; sleep 5'"

        outcome = described_class.run(command: command, chdir: Dir.pwd, timeout: 0.5)

        expect(outcome.timed_out).to be(true)
        expect(outcome.exit_code).to be_nil
        # Wall-clock proves the runner cut the command off at the timeout, not
        # after the full sleep — large margin keeps this non-flaky.
        expect(outcome.duration).to be < 3.0

        pid = Integer(File.read(pid_file).strip)
        expect(wait_dead(pid)).to be(true), "process group #{pid} survived the TERM"
      end
    end
  end

  describe '.run spawn failure' do
    it 'returns a nil exit code with a stderr message (distinct from a non-zero exit)' do
      outcome = described_class.run(
        command: "sh -c 'exit 0'", chdir: File.join(Dir.pwd, 'no-such-dir-owl-spec'), timeout: 5
      )

      expect(outcome.exit_code).to be_nil
      expect(outcome.stderr).not_to be_empty
      expect(outcome.timed_out).to be(false)
    end
  end

  describe '.run duration' do
    it 'records a non-negative duration' do
      outcome = described_class.run(command: "sh -c 'exit 0'", chdir: Dir.pwd, timeout: 5)

      expect(outcome.duration).to be_a(Numeric)
      expect(outcome.duration).to be >= 0
    end
  end
end
