# frozen_string_literal: true

require_relative 'internal/engine'
require_relative 'internal/gate'

module Owl
  # Objective verification: Owl runs the project's configured verification
  # command itself (subprocess, exit code) and authors the `verification`
  # artifact, so a green result cannot be faked by an agent self-report. The
  # completion gate lives in `Owl::Steps::Api.complete` for steps flagged
  # `verify: true`. See RFC/brief for TASK-0012.
  module Verification
    module Api
      module_function

      # Run the verification command and overwrite the `verification` artifact.
      # `command`/`timeout` default to `settings.verification.*`; `runner` is
      # injectable so specs never run a real suite.
      def run(root:, task_id:, command: nil, timeout: nil, runner: Internal::CommandRunner)
        Internal::Engine.run(root: root, task_id: task_id, command: command, timeout: timeout, runner: runner)
      end

      # Evaluate the completion gate for a step. Returns a non-applicable Ok for
      # steps without `verify: true`, a fail-open Ok (with warning) when no
      # command is configured, an Ok on pass/partial, or an Err that blocks
      # completion on failure.
      def gate(root:, task_id:, step_id:, runner: Internal::CommandRunner)
        Internal::Gate.call(root: root, task_id: task_id, step_id: step_id, runner: runner)
      end

      # The configured verification command, or nil when unset (fail-open).
      def configured_command(root:)
        Internal::Engine.config_command(root: root)
      end
    end
  end
end
