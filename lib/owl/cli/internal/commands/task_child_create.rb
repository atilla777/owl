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
            parent_id = positional.first
            unless parent_id && options[:workflow] && options[:title]
              return JsonPrinter.failure(
                stderr,
                code: :invalid_arguments,
                message: 'TASK-ID positional, --workflow KEY, and --title TITLE are required.'
              )
            end

            root = TaskSupport.resolve_root(options[:root], cwd, stderr: stderr)
            return root if root.is_a?(Integer)

            brief_body = load_brief_body(options[:brief_path], stderr)
            return brief_body if brief_body.is_a?(Integer)

            result = Owl::Tasks::Api.child_create(
              root: root,
              parent_id: parent_id,
              workflow: options[:workflow],
              title: options[:title],
              brief_body: brief_body
            )
            return JsonPrinter.failure(stderr, **TaskSupport.error_payload(result)) if result.err?

            payload = {
              ok: true,
              parent_id: parent_id.to_s,
              task: result.value[:payload]
            }
            paths = Owl::Tasks::Api.local_paths(root: root, task_id: result.value[:task_id])
            payload[:task_path] = paths.value[:task_file].task_path if paths.ok?
            JsonPrinter.success(stdout, payload)
          rescue OptionParser::ParseError => e
            JsonPrinter.failure(stderr, code: :invalid_arguments, message: e.message)
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

          def parse_options(argv)
            options = { root: nil, workflow: nil, title: nil, brief_path: nil }
            parser = OptionParser.new do |opts|
              opts.banner = 'Usage: owl task child create TASK-ID --workflow KEY --title TITLE ' \
                            '[--brief PATH] [--root PATH] [--json]'
              opts.on('--workflow KEY', String) { |v| options[:workflow] = v }
              opts.on('--title TITLE', String) { |v| options[:title] = v }
              opts.on('--brief PATH', String, 'Pre-author child brief.md from PATH; marks brief step done') do |v|
                options[:brief_path] = v
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
