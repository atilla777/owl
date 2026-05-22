# frozen_string_literal: true

require 'yaml'

require_relative '../../result'
require_relative '../../storage/api'
require_relative 'output_spec'
require_relative 'report_paths'

module Owl
  module Subagents
    module Internal
      # Default backend that implements the env-agnostic spawn_subagent
      # contract (RFC #1 §4, knowledge entry 46) via the local filesystem.
      #
      # `run` serializes the input bundle to `.owl/local/spawns/...` so the
      # external runtime (Claude Code Task tool, Codex, OpenCode, etc.)
      # can pick it up. If a matching report already exists in
      # `.owl/local/reports/...` (written by an external subagent via
      # `owl step report --body -`), the backend parses and returns it.
      # Otherwise it returns `final_state: :error` with an error message
      # asking for the report to be produced. Real spawning lives in
      # runtime-specific backends (RFC #1 §8 F-2 follow-up tasks).
      class FilesystemReportBackend
        attr_reader :root

        def initialize(root:)
          @root = root
        end

        # @return [Hash] result matching RFC §4.2 outputs:
        #   {final_state:, report_body:, report_artifacts:, tool_usage_summary:, error_message:}
        def run(task_id:, step_id:, input_bundle:, output_spec: nil)
          write_input(task_id: task_id, step_id: step_id, input_bundle: input_bundle)

          report_path = Owl::Subagents::Internal::ReportPaths.report_path(
            root: root, task_id: task_id, step_id: step_id
          )

          unless Owl::Storage::Api.exists?(path: report_path)
            return {
              final_state: :error,
              report_body: nil,
              report_artifacts: [],
              tool_usage_summary: [],
              error_message:
                "No report at #{report_path}. External runtime must invoke " \
                "`owl step report --task-id #{task_id} --step-id #{step_id} --body -` " \
                'before this backend can return a report. See RFC #1 §5.'
            }
          end

          read_result = Owl::Storage::Api.read(path: report_path)
          return error_result(read_result.message) if read_result.respond_to?(:err?) && read_result.err?

          body = read_result.respond_to?(:value) ? read_result.value : read_result.to_s
          validation = Owl::Subagents::Internal::OutputSpec.validate(body, output_spec: output_spec)
          if validation.err?
            return {
              final_state: :error,
              report_body: body,
              report_artifacts: [],
              tool_usage_summary: [],
              error_message: "Report failed output_spec validation: #{validation.details.inspect}"
            }
          end

          {
            final_state: final_state_from(validation.value),
            report_body: body,
            report_artifacts: [],
            tool_usage_summary: [],
            error_message: nil
          }
        end

        private

        def write_input(task_id:, step_id:, input_bundle:)
          path = Owl::Subagents::Internal::ReportPaths.spawn_input_path(
            root: root, task_id: task_id, step_id: step_id
          )
          Owl::Storage::Api.mkdir_p(path: path.dirname)
          Owl::Storage::Api.write(path: path, contents: YAML.dump(stringify(input_bundle)))
        end

        def stringify(bundle)
          case bundle
          when Hash then bundle.each_with_object({}) { |(k, v), h| h[k.to_s] = stringify(v) }
          when Array then bundle.map { |v| stringify(v) }
          else bundle
          end
        end

        def final_state_from(parsed)
          status = parsed[:frontmatter]['status'].to_s
          case status
          when 'returned_normally', 'do_not_use' then :returned_normally
          when 'interrupted' then :interrupted
          when 'budget_exceeded' then :budget_exceeded
          else :error
          end
        end

        def error_result(message)
          {
            final_state: :error,
            report_body: nil,
            report_artifacts: [],
            tool_usage_summary: [],
            error_message: message
          }
        end
      end
    end
  end
end
