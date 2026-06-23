# frozen_string_literal: true

require 'open3'
require 'timeout'

module Owl
  module Verification
    module Internal
      # Default runner for the objective verification command. Executes the
      # configured command string through a shell (so `bundle exec rspec` and
      # the like work verbatim), capturing combined output, exit code, and
      # whether it exceeded the timeout. Injectable so specs never run a real
      # suite (mirrors `Owl::Upgrade::Internal::ShellRunner`).
      module CommandRunner
        Outcome = Struct.new(:exit_code, :stdout, :stderr, :timed_out, :duration, keyword_init: true)

        module_function

        def run(command:, chdir:, timeout:)
          started = monotonic
          execute(command: command, chdir: chdir, timeout: timeout, started: started)
        rescue StandardError => e
          # A failure to even spawn the process (e.g. chdir missing) is a run
          # error, distinct from a non-zero test exit: signalled by exit_code nil.
          Outcome.new(exit_code: nil, stdout: '', stderr: e.message, timed_out: false, duration: elapsed(started))
        end

        def execute(command:, chdir:, timeout:, started:)
          Open3.popen3(command, chdir: chdir.to_s, pgroup: true) do |stdin, out, err, wait_thr|
            stdin.close
            out_reader = Thread.new { out.read }
            err_reader = Thread.new { err.read }
            collect(out_reader, err_reader, wait_thr, timeout, started)
          end
        end

        def collect(out_reader, err_reader, wait_thr, timeout, started)
          status = Timeout.timeout(timeout) { wait_thr.value }
          Outcome.new(
            exit_code: status.exitstatus, stdout: out_reader.value, stderr: err_reader.value,
            timed_out: false, duration: elapsed(started)
          )
        rescue Timeout::Error
          terminate(wait_thr.pid)
          Outcome.new(
            exit_code: nil, stdout: drain(out_reader), stderr: drain(err_reader),
            timed_out: true, duration: elapsed(started)
          )
        end

        def terminate(pid)
          Process.kill('TERM', -pid)
        rescue StandardError
          nil
        end

        def drain(reader)
          reader.kill
          ''
        end

        def elapsed(started)
          (monotonic - started).round(3)
        end

        def monotonic
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end
      end
    end
  end
end
