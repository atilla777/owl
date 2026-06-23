# frozen_string_literal: true

require_relative '../../result'
require_relative '../../storage/api'

module Owl
  module Verification
    module Internal
      # Renders and overwrites the `verification` artifact with an objective,
      # Owl-authored result. The agent never writes the status here — that is
      # what makes the gate trustworthy. The rendered document satisfies the
      # seeded `verification` artifact type (front matter + required sections).
      module ReportWriter
        OUTPUT_TAIL_LINES = 50

        module_function

        def call(path:, status:, command:, outcome:, output_tail:)
          contents = render(status: status, command: command, outcome: outcome, output_tail: output_tail)
          # Storage::Api.write creates the parent directory atomically; no
          # direct filesystem access here (constitution §5.11 / no-direct-fs).
          Owl::Storage::Api.write(path: path, contents: contents)
        end

        def render(status:, command:, outcome:, output_tail:)
          <<~MD
            #{front_matter(status, outcome)}

            ## Summary

            #{summary_line(status, outcome)}

            ## Commands

            - `#{command}`

            ## Outcomes

            #{outcomes_block(status, outcome, output_tail)}

            ## Not run

            None — Owl ran the configured verification command objectively.

            ## Failures or blockers

            #{failures_block(status, output_tail)}

            ## Residual risks

            None recorded by the objective run.
          MD
        end

        def front_matter(status, outcome)
          lines = ['---', "status: #{status}", "summary: #{summary_line(status, outcome)}"]
          lines << "partial_reason: #{partial_reason(outcome)}" if partial_reason(outcome)
          lines << '---'
          lines.join("\n")
        end

        def summary_line(status, outcome)
          if outcome.timed_out
            "Objective verification timed out after #{outcome.duration}s (status: #{status})."
          elsif outcome.exit_code.nil?
            "Objective verification could not run the command (status: #{status})."
          else
            "Objective verification #{status} (exit #{outcome.exit_code}, #{outcome.duration}s)."
          end
        end

        def outcomes_block(status, outcome, output_tail)
          exit_label = outcome.exit_code.nil? ? 'n/a (command did not exit)' : outcome.exit_code
          [
            "- status: #{status}",
            "- exit_code: #{exit_label}",
            "- timed_out: #{outcome.timed_out}",
            "- duration_seconds: #{outcome.duration}",
            '',
            'Output tail:',
            '',
            '```',
            output_tail.to_s.empty? ? '(no output captured)' : output_tail,
            '```'
          ].join("\n")
        end

        def failures_block(status, output_tail)
          return 'None — the configured verification command passed.' if status == 'passed'

          tail = output_tail.to_s.empty? ? '(no output captured)' : output_tail
          "The verification command did not pass. Output tail:\n\n```\n#{tail}\n```"
        end

        def partial_reason(outcome)
          return 'timeout' if outcome.timed_out
          return 'run_error' if outcome.exit_code.nil?

          nil
        end
      end
    end
  end
end
