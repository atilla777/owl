# frozen_string_literal: true

require 'optparse'

require_relative '../../../tasks/api'
require_relative '../json_printer'
require_relative '../user_file_reader'
require_relative 'task_support'

module Owl
  module Cli
    module Internal
      module Commands
        module TaskChildCreate
          module_function

          def run(argv:, stdout:, stderr:, cwd:, env: ENV.to_h) # rubocop:disable Lint/UnusedMethodArgument
            options, positional = parse_options(argv)
            # Parent id is a positional argument; `--parent PARENT-ID` is accepted
            # as a back-compat alias (older skill/README docs taught that form).
            # The positional wins when both are given.
            parent_id = positional.first || options[:parent]
            unless parent_id && options[:workflow] && options[:title]
              return JsonPrinter.failure(
                stderr,
                code: :invalid_arguments,
                message: 'TASK-ID positional, --workflow KEY, and --title TITLE are required.'
              )
            end

            if options[:brief_path] && !options[:brief_body].nil?
              return JsonPrinter.failure(
                stderr,
                code: :invalid_arguments,
                message: '--brief and --brief-body are mutually exclusive; pass only one.'
              )
            end

            root = TaskSupport.resolve_root(options[:root], cwd, stderr: stderr)
            return root if root.is_a?(Integer)

            brief_body = resolve_brief_body(options, stderr)
            return brief_body if brief_body.is_a?(Integer)

            result = Owl::Tasks::Api.child_create(
              root: root,
              parent_id: parent_id,
              workflow: options[:workflow],
              title: options[:title],
              brief_body: brief_body,
              validate_brief: !options[:brief_body].nil?
            )
            return JsonPrinter.failure(stderr, **TaskSupport.error_payload(result)) if result.err?

            JsonPrinter.success(stdout, success_payload(parent_id: parent_id, root: root, result: result))
          rescue OptionParser::ParseError => e
            JsonPrinter.failure(stderr, code: :invalid_arguments, message: e.message)
          end

          def success_payload(parent_id:, root:, result:)
            payload = { ok: true, parent_id: parent_id.to_s, task: result.value[:payload] }
            paths = Owl::Tasks::Api.local_paths(root: root, task_id: result.value[:task_id])
            payload[:task_path] = paths.value[:task_file].task_path if paths.ok?
            payload
          end

          # Resolve the brief markdown from whichever source the invoker used:
          # `--brief PATH` (read a host file) or `--brief-body BODY` (inline, or
          # `-` to read stdin, mirroring `workflow context set --body -`). The
          # two are mutually exclusive; that is enforced by the caller.
          def resolve_brief_body(options, stderr)
            return load_brief_body(options[:brief_path], stderr) unless options[:brief_path].nil?
            return read_inline_brief_body(options[:brief_body], stderr) unless options[:brief_body].nil?

            nil
          end

          def load_brief_body(path, stderr)
            return nil if path.nil?

            result = Owl::Cli::Internal::UserFileReader.read(path: path)
            if result.err?
              return JsonPrinter.failure(
                stderr,
                code: :brief_file_missing,
                message: "--brief file not found: #{path}"
              )
            end
            result.value
          end

          def read_inline_brief_body(body_opt, stderr)
            return $stdin.read if body_opt == '-'

            body_opt
          rescue StandardError => e
            JsonPrinter.failure(stderr, code: :invalid_arguments, message: "Failed to read brief body: #{e.message}")
          end

          def parse_options(argv)
            options = { root: nil, workflow: nil, title: nil, brief_path: nil, brief_body: nil, parent: nil }
            parser = OptionParser.new do |opts|
              opts.banner = 'Usage: owl task child create TASK-ID --workflow KEY --title TITLE ' \
                            '[--brief PATH | --brief-body -] [--root PATH] [--json]'
              opts.on('--parent PARENT-ID', String,
                      'Back-compat alias for the positional parent id') do |v|
                options[:parent] = v
              end
              opts.on('--workflow KEY', String) { |v| options[:workflow] = v }
              opts.on('--title TITLE', String) { |v| options[:title] = v }
              opts.on('--brief PATH', String, 'Pre-author child brief.md from PATH; marks brief step done') do |v|
                options[:brief_path] = v
              end
              opts.on('--brief-body BODY', String,
                      'Pre-author child brief.md from BODY (use - for stdin); marks brief step done. ' \
                      'Mutually exclusive with --brief') do |v|
                options[:brief_body] = v
              end
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
