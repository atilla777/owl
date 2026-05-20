# frozen_string_literal: true

require 'optparse'

require_relative '../../../artifacts/api'
require_relative '../json_printer'
require_relative 'task_support'

module Owl
  module Cli
    module Internal
      module Commands
        module ArtifactTypeNew
          module_function

          def run(argv:, stdout:, stderr:, cwd:, env: ENV.to_h) # rubocop:disable Lint/UnusedMethodArgument
            options = parse_options(argv)
            unless options[:id]
              return JsonPrinter.failure(stderr, code: :invalid_arguments, message: '--id is required.')
            end

            root = TaskSupport.resolve_root(options[:root], cwd, stderr: stderr)
            return root if root.is_a?(Integer)

            body = read_body(options[:body], stderr: stderr)
            return body if body.is_a?(Integer)

            result = Owl::Artifacts::Api.scaffold(
              root: root,
              id: options[:id],
              body: body,
              force: options[:force]
            )
            return JsonPrinter.failure(stderr, **TaskSupport.error_payload(result)) if result.err?

            payload = { ok: true }.merge(result.value)
            paths = Owl::Artifacts::Api.local_paths(root: root, key: result.value[:id])
            if paths.ok?
              payload[:path] = paths.value.source_path
              payload[:template_path] = paths.value.template_path
            end
            JsonPrinter.success(stdout, payload)
          rescue OptionParser::ParseError => e
            JsonPrinter.failure(stderr, code: :invalid_arguments, message: e.message)
          end

          def parse_options(argv)
            options = { id: nil, body: nil, root: nil, force: false }
            parser = OptionParser.new do |opts|
              opts.banner = 'Usage: owl artifact-type new --id ID [--body -] [--force] [--root PATH] [--json]'
              opts.on('--id ID', String) { |v| options[:id] = v }
              opts.on('--body BODY', String) { |v| options[:body] = v }
              opts.on('--force', 'Overwrite existing artifact type source') { options[:force] = true }
              opts.on('--root PATH', String) { |v| options[:root] = v }
              opts.on('--json', 'Force JSON output (default)') { options[:json] = true }
            end
            parser.parse!(argv)
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
