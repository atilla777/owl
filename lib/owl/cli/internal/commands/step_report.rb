# frozen_string_literal: true

require 'optparse'

require_relative '../../../storage/api'
require_relative '../../../subagents/internal/output_spec'
require_relative '../../../subagents/internal/report_paths'
require_relative '../json_printer'
require_relative 'task_support'

module Owl
  module Cli
    module Internal
      module Commands
        # `owl step report` — env-agnostic CLI for reading and writing
        # subagent reports (RFC #1 §5, knowledge entry 46).
        #
        # Write:
        #   owl step report --task-id ID --step-id ID --body -|PATH [--validate]
        #
        # Read:
        #   owl step report --task-id ID --step-id ID --read
        #
        # Write mode reads the body from stdin (`--body -`) or a file path
        # and saves it to `.owl/local/reports/<TASK-ID>/<STEP-ID>.md` via
        # Owl::Storage::Api. With `--validate`, the body is checked against
        # the default markdown-with-frontmatter output_spec before write.
        #
        # Read mode prints the saved body to stdout. Exit codes:
        # 0 success, 1 not found, 2 validation failure.
        module StepReport
          module_function

          def run(argv:, stdout:, stderr:, cwd:, env: ENV.to_h) # rubocop:disable Lint/UnusedMethodArgument
            options = parse_options(argv)
            unless options[:task_id] && options[:step_id]
              return JsonPrinter.failure(
                stderr,
                code: :invalid_arguments,
                message: '--task-id and --step-id are required.'
              )
            end

            root = TaskSupport.resolve_root(options[:root], cwd, stderr: stderr)
            return root if root.is_a?(Integer)

            if options[:read]
              read_mode(stdout: stdout, stderr: stderr, root: root, options: options)
            else
              write_mode(stdin: $stdin, stdout: stdout, stderr: stderr, root: root, options: options)
            end
          rescue OptionParser::ParseError => e
            JsonPrinter.failure(stderr, code: :invalid_arguments, message: e.message)
          end

          def write_mode(stdin:, stdout:, stderr:, root:, options:)
            unless options[:body]
              return JsonPrinter.failure(
                stderr,
                code: :invalid_arguments,
                message: '--body is required in write mode (use `-` to read from stdin).'
              )
            end

            body = options[:body] == '-' ? stdin.read : safe_read_file(options[:body])
            return JsonPrinter.failure(stderr, code: :body_unreadable, message: body[:error]) if body.is_a?(Hash)

            if options[:validate]
              validation = Owl::Subagents::Internal::OutputSpec.validate(body)
              if validation.err?
                stderr.puts(JSON.generate({
                                            ok: false,
                                            error: {
                                              code: validation.code.to_s,
                                              message: validation.message,
                                              details: validation.details
                                            }
                                          }))
                return 2
              end
            end

            path = Owl::Subagents::Internal::ReportPaths.report_path(
              root: root, task_id: options[:task_id], step_id: options[:step_id]
            )
            Owl::Storage::Api.mkdir_p(path: path.dirname)
            Owl::Storage::Api.write(path: path, contents: body)

            JsonPrinter.success(stdout, {
                                  ok: true,
                                  task_id: options[:task_id],
                                  step_id: options[:step_id],
                                  path: path.to_s,
                                  bytes: body.bytesize
                                })
          end

          def read_mode(stdout:, stderr:, root:, options:)
            path = Owl::Subagents::Internal::ReportPaths.report_path(
              root: root, task_id: options[:task_id], step_id: options[:step_id]
            )
            unless Owl::Storage::Api.exists?(path: path)
              stderr.puts(JSON.generate({
                                          ok: false,
                                          error: {
                                            code: 'report_not_found',
                                            message: "No subagent report at #{path}.",
                                            details: { task_id: options[:task_id], step_id: options[:step_id],
                                                       path: path.to_s }
                                          }
                                        }))
              return 1
            end

            read = Owl::Storage::Api.read(path: path)
            if read.respond_to?(:err?) && read.err?
              return JsonPrinter.failure(stderr, **TaskSupport.error_payload(read))
            end

            body = read.respond_to?(:value) ? read.value : read.to_s
            stdout.write(body)
            stdout.write("\n") unless body.end_with?("\n")
            0
          end

          def safe_read_file(path)
            File.read(path)
          rescue Errno::ENOENT
            { error: "File not found: #{path}" }
          rescue StandardError => e
            { error: "Failed to read #{path}: #{e.message}" }
          end

          def parse_options(argv)
            options = { root: nil, task_id: nil, step_id: nil, body: nil, read: false, validate: false }
            parser = OptionParser.new do |opts|
              opts.banner = 'Usage: owl step report --task-id ID --step-id ID [--body -|PATH | --read] [--validate]'
              opts.on('--task-id ID', String) { |v| options[:task_id] = v }
              opts.on('--step-id ID', String) { |v| options[:step_id] = v }
              opts.on('--body BODY', String) { |v| options[:body] = v }
              opts.on('--read', 'Read existing report and print body to stdout.') { options[:read] = true }
              opts.on('--validate', 'Validate body against default output_spec before writing.') do
                options[:validate] = true
              end
              opts.on('--root PATH', String) { |v| options[:root] = v }
              opts.on('--json', 'Force JSON output (default).') { options[:json] = true }
            end
            parser.parse(argv)
            options
          end
        end
      end
    end
  end
end
