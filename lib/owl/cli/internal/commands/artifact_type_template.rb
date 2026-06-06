# frozen_string_literal: true

require 'optparse'

require_relative '../../../artifacts/api'
require_relative '../json_printer'
require_relative 'task_support'

module Owl
  module Cli
    module Internal
      module Commands
        # `owl artifact-type template <show|set|validate> ID [--template NAME]`.
        # Provides a CLI surface for reading, writing, and validating artifact
        # template bodies, closing the "edit templates/default.md by hand" gap.
        module ArtifactTypeTemplate
          module_function

          def run(argv:, stdout:, stderr:, cwd:, env: ENV.to_h) # rubocop:disable Lint/UnusedMethodArgument
            sub = argv.first
            rest = argv.drop(1)
            case sub
            when 'show'     then show(argv: rest, stdout: stdout, stderr: stderr, cwd: cwd)
            when 'set'      then set(argv: rest, stdout: stdout, stderr: stderr, cwd: cwd)
            when 'validate' then validate(argv: rest, stdout: stdout, stderr: stderr, cwd: cwd)
            else
              JsonPrinter.failure(stderr, code: :unknown_command,
                                          message: "Unknown command: 'artifact-type template #{sub}'.")
            end
          end

          def show(argv:, stdout:, stderr:, cwd:)
            options, id, root = prepare(argv, cwd, stderr)
            return id if id.is_a?(Integer)

            result = Owl::Artifacts::Api.template_show(root: root, id: id, template: options[:template])
            return JsonPrinter.failure(stderr, **TaskSupport.error_payload(result)) if result.err?

            JsonPrinter.success(stdout, { ok: true }.merge(result.value))
          rescue OptionParser::ParseError => e
            JsonPrinter.failure(stderr, code: :invalid_arguments, message: e.message)
          end

          def set(argv:, stdout:, stderr:, cwd:)
            options, id, root = prepare(argv, cwd, stderr)
            return id if id.is_a?(Integer)

            body = read_body(options[:body], stderr: stderr)
            return body if body.is_a?(Integer)
            if body.nil?
              return JsonPrinter.failure(stderr, code: :invalid_arguments, message: '--body is required for set.')
            end

            result = Owl::Artifacts::Api.template_set(root: root, id: id, body: body, template: options[:template])
            return JsonPrinter.failure(stderr, **TaskSupport.error_payload(result)) if result.err?

            JsonPrinter.success(stdout, { ok: true }.merge(result.value))
          rescue OptionParser::ParseError => e
            JsonPrinter.failure(stderr, code: :invalid_arguments, message: e.message)
          end

          def validate(argv:, stdout:, stderr:, cwd:)
            options, id, root = prepare(argv, cwd, stderr)
            return id if id.is_a?(Integer)

            result = Owl::Artifacts::Api.template_validate(root: root, id: id, template: options[:template])
            return JsonPrinter.failure(stderr, **TaskSupport.error_payload(result)) if result.err?

            JsonPrinter.success(stdout, { ok: true }.merge(result.value))
          rescue OptionParser::ParseError => e
            JsonPrinter.failure(stderr, code: :invalid_arguments, message: e.message)
          end

          def prepare(argv, cwd, stderr)
            options = parse_options(argv)
            root = TaskSupport.resolve_root(options[:root], cwd, stderr: stderr)
            return [options, root, nil] if root.is_a?(Integer)

            unless options[:id]
              return [options, JsonPrinter.failure(stderr, code: :invalid_arguments, message: 'ID is required.'), root]
            end

            [options, options[:id], root]
          end

          def parse_options(argv)
            options = { id: nil, template: 'default', body: nil, root: nil }
            parser = OptionParser.new do |opts|
              opts.banner = 'Usage: owl artifact-type template <show|set|validate> ID ' \
                            '[--template NAME] [--body -] [--root PATH] [--json]'
              opts.on('--template NAME', String) { |v| options[:template] = v }
              opts.on('--body BODY', String) { |v| options[:body] = v }
              opts.on('--root PATH', String) { |v| options[:root] = v }
              opts.on('--json', 'Force JSON output (default)') { options[:json] = true }
            end
            parser.parse!(argv)
            options[:id] ||= argv.shift
            options
          end

          def read_body(body_opt, stderr:)
            return nil if body_opt.nil?

            return $stdin.read if body_opt == '-'

            body_opt
          rescue StandardError => e
            JsonPrinter.failure(stderr, code: :invalid_arguments, message: "Failed to read body: #{e.message}")
          end
        end
      end
    end
  end
end
