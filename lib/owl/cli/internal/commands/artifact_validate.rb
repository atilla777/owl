# frozen_string_literal: true

require 'optparse'

require_relative '../../../validation/api'
require_relative '../json_printer'
require_relative 'task_support'

module Owl
  module Cli
    module Internal
      module Commands
        module ArtifactValidate
          module_function

          def run(argv:, stdout:, stderr:, cwd:, env: ENV.to_h) # rubocop:disable Lint/UnusedMethodArgument
            options, positional = parse_options(argv)
            task_id = positional[0]
            artifact_key = positional[1]
            unless task_id
              return JsonPrinter.failure(
                stderr,
                code: :invalid_arguments,
                message: 'TASK-ID positional argument is required.'
              )
            end

            root = TaskSupport.resolve_root(options[:root], cwd, stderr: stderr)
            return root if root.is_a?(Integer)

            if artifact_key
              run_single(root: root, task_id: task_id, artifact_key: artifact_key, stdout: stdout, stderr: stderr)
            else
              run_all(root: root, task_id: task_id, stdout: stdout, stderr: stderr)
            end
          rescue OptionParser::ParseError => e
            JsonPrinter.failure(stderr, code: :invalid_arguments, message: e.message)
          end

          def run_single(root:, task_id:, artifact_key:, stdout:, stderr:)
            result = Owl::Validation::Api.artifact(root: root, task_id: task_id, artifact_key: artifact_key)
            return JsonPrinter.failure(stderr, **TaskSupport.error_payload(result)) if result.err?

            value = result.value
            JsonPrinter.success(stdout, {
                                  ok: true,
                                  valid: value[:valid],
                                  violations: value[:violations],
                                  artifact: {
                                    key: value[:artifact_key],
                                    path: value[:descriptor][:path],
                                    exists: value[:descriptor][:exists]
                                  }
                                })
          end

          def run_all(root:, task_id:, stdout:, stderr:)
            result = Owl::Validation::Api.task(root: root, task_id: task_id)
            return JsonPrinter.failure(stderr, **TaskSupport.error_payload(result)) if result.err?

            JsonPrinter.success(stdout, {
                                  ok: true,
                                  all_valid: result.value[:all_valid],
                                  results: result.value[:results].map do |r|
                                    {
                                      artifact_key: r[:artifact_key],
                                      valid: r[:valid],
                                      violations: r[:violations]
                                    }
                                  end
                                })
          end

          def parse_options(argv)
            options = { root: nil }
            parser = OptionParser.new do |opts|
              opts.banner = 'Usage: owl artifact validate TASK-ID [ARTIFACT-KEY] [--root PATH] [--json]'
              opts.on('--root PATH', String) { |v| options[:root] = v }
              opts.on('--json', 'Force JSON output (default)') { options[:json] = true }
            end
            positional = parser.parse(argv)
            [options, positional]
          end
        end
      end
    end
  end
end
