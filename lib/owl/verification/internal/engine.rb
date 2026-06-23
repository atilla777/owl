# frozen_string_literal: true

require_relative '../../result'
require_relative '../../config/api'
require_relative '../../artifacts/internal/task_artifact_resolver'
require_relative 'command_runner'
require_relative 'report_writer'

module Owl
  module Verification
    module Internal
      # Objective verification engine: runs the configured command as a
      # subprocess, derives the status from its exit code, and overwrites the
      # `verification` artifact itself. The status is never agent-authored.
      module Engine
        DEFAULT_TIMEOUT_SECONDS = 1800
        COMMAND_KEY = 'settings.verification.command'
        TIMEOUT_KEY = 'settings.verification.timeout_seconds'

        module_function

        def run(root:, task_id:, command: nil, timeout: nil, runner: CommandRunner)
          cmd = command || config_command(root: root)
          if cmd.nil?
            return Result.err(
              code: :verification_command_missing,
              message: "No verification command configured (#{COMMAND_KEY}) and none supplied.",
              details: { task_id: task_id.to_s }
            )
          end

          execute(root: root, task_id: task_id, command: cmd, timeout: timeout, runner: runner)
        end

        def execute(root:, task_id:, command:, timeout:, runner:)
          path_result = artifact_path(root: root, task_id: task_id)
          return path_result if path_result.err?

          outcome = runner.run(command: command, chdir: root, timeout: timeout || config_timeout(root: root))
          status = classify(outcome)
          output_tail = tail(outcome)

          write = ReportWriter.call(
            path: path_result.value, status: status, command: command, outcome: outcome, output_tail: output_tail
          )
          return write if write.err?

          Result.ok(
            status: status, exit_code: outcome.exit_code, command: command,
            output_tail: output_tail, duration: outcome.duration, timed_out: outcome.timed_out,
            artifact_path: path_result.value.to_s
          )
        end

        def classify(outcome)
          return 'failed' if outcome.timed_out
          return 'failed' if outcome.exit_code.nil?

          outcome.exit_code.zero? ? 'passed' : 'failed'
        end

        # Combined stdout+stderr tail, last N lines, for the artifact record.
        def tail(outcome, lines: ReportWriter::OUTPUT_TAIL_LINES)
          combined = [outcome.stdout, outcome.stderr].map(&:to_s).reject(&:empty?).join("\n")
          combined.lines.last(lines).join.rstrip
        end

        def artifact_path(root:, task_id:)
          descriptor = Owl::Artifacts::Internal::TaskArtifactResolver.call(
            root: root, task_id: task_id, artifact_key: 'verification'
          )
          return descriptor if descriptor.err?

          Result.ok(descriptor.value[:path])
        end

        # The configured command string, or nil when unset/blank (fail-open).
        def config_command(root:)
          value = read_setting(root: root, key: COMMAND_KEY)
          return nil unless value.is_a?(String)

          stripped = value.strip
          stripped.empty? ? nil : stripped
        end

        def config_timeout(root:)
          value = read_setting(root: root, key: TIMEOUT_KEY)
          return value if value.is_a?(Integer) && value.positive?

          DEFAULT_TIMEOUT_SECONDS
        end

        def read_setting(root:, key:)
          result = Owl::Config::Api.read_key(root: root, key: key)
          return nil if result.err?

          result.value[:value]
        end
      end
    end
  end
end
