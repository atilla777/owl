# frozen_string_literal: true

require 'optparse'

require_relative '../../../artifacts/api'
require_relative '../json_printer'
require_relative 'task_support'

module Owl
  module Cli
    module Internal
      module Commands
        # `owl artifact-type register ID` / `owl artifact-type unregister ID`.
        # Explicit registry inclusion/removal — `new` deliberately does not
        # register, so ad-hoc experiments do not pollute .owl/artifacts.yaml.
        module ArtifactTypeRegister
          module_function

          def run(argv:, stdout:, stderr:, cwd:, env: ENV.to_h) # rubocop:disable Lint/UnusedMethodArgument
            options = parse_options(argv)
            id = options[:id] || argv.shift
            return JsonPrinter.failure(stderr, code: :invalid_arguments, message: 'ID is required.') unless id

            root = TaskSupport.resolve_root(options[:root], cwd, stderr: stderr)
            return root if root.is_a?(Integer)

            result = Owl::Artifacts::Api.register(
              root: root, id: id, source: options[:source], managed: options[:managed], force: options[:force]
            )
            return JsonPrinter.failure(stderr, **TaskSupport.error_payload(result)) if result.err?

            JsonPrinter.success(stdout, { ok: true }.merge(result.value))
          rescue OptionParser::ParseError => e
            JsonPrinter.failure(stderr, code: :invalid_arguments, message: e.message)
          end

          def unregister(argv:, stdout:, stderr:, cwd:, env: ENV.to_h) # rubocop:disable Lint/UnusedMethodArgument
            options = parse_options(argv)
            id = options[:id] || argv.shift
            return JsonPrinter.failure(stderr, code: :invalid_arguments, message: 'ID is required.') unless id

            root = TaskSupport.resolve_root(options[:root], cwd, stderr: stderr)
            return root if root.is_a?(Integer)

            result = Owl::Artifacts::Api.unregister(root: root, id: id)
            return JsonPrinter.failure(stderr, **TaskSupport.error_payload(result)) if result.err?

            JsonPrinter.success(stdout, { ok: true }.merge(result.value))
          rescue OptionParser::ParseError => e
            JsonPrinter.failure(stderr, code: :invalid_arguments, message: e.message)
          end

          def parse_options(argv)
            options = { id: nil, source: nil, managed: false, root: nil, force: false }
            parser = OptionParser.new do |opts|
              opts.banner = 'Usage: owl artifact-type register ID [--source PATH] [--managed] ' \
                            '[--force] [--root PATH] [--json]'
              opts.on('--source PATH', String) { |v| options[:source] = v }
              opts.on('--managed', 'Mark as Owl-managed (read-only); default is project-owned') do
                options[:managed] = true
              end
              opts.on('--force', 'Overwrite an existing registry entry') { options[:force] = true }
              opts.on('--root PATH', String) { |v| options[:root] = v }
              opts.on('--json', 'Force JSON output (default)') { options[:json] = true }
            end
            parser.parse!(argv)
            options
          end
        end
      end
    end
  end
end
