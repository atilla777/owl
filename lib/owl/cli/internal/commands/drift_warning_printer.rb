# frozen_string_literal: true

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
