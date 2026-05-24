# frozen_string_literal: true

require 'json'

require_relative '../json_printer'

module Owl
  module Cli
    module Internal
      module Commands
        module DriftWarningPrinter
          module_function

          def call(events, stderr:)
            events.each do |event|
              stderr.puts(format_event(event))
            end
          end

          # Policy-aware variant. Returns nil when the step should continue,
          # or an Integer exit code when the policy is :block (RFC #1 §4).
          def call_with_policy(events, policy:, stderr:, task_id:, step_id:)
            return nil if events.empty? || policy == :ignore

            if policy == :warn
              call(events, stderr: stderr)
              return nil
            end

            JsonPrinter.failure(
              stderr,
              code: :drift_block,
              message: "Drift detected for step #{step_id} with drift_policy=block.",
              details: {
                task_id: task_id,
                step_id: step_id,
                events: events
              },
              error_class: :recoverable
            )
          end

          def format_event(event)
            case event[:type]
            when :modified
              "WARNING: artifact_modified_after_complete: step=#{event[:step_id]} " \
              "artifact=#{event[:artifact_key]} recorded=#{short(event[:recorded_sha])} " \
              "actual=#{short(event[:actual_sha])}"
            when :missing
              "WARNING: artifact_modified_after_complete: step=#{event[:step_id]} " \
              "artifact=#{event[:artifact_key]} recorded=#{short(event[:recorded_sha])} actual=<missing>"
            else
              "WARNING: artifact_modified_after_complete: #{event.inspect}"
            end
          end

          def short(sha)
            return '<nil>' if sha.nil?

            sha.to_s[0, 8]
          end
        end
      end
    end
  end
end
