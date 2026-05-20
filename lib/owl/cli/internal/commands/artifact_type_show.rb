# frozen_string_literal: true

require 'optparse'

require_relative '../../../artifacts/api'
require_relative '../json_printer'
require_relative 'task_support'

module Owl
  module Cli
    module Internal
      module Commands
        module ArtifactTypeShow
          module_function

          def run(argv:, stdout:, stderr:, cwd:, env: ENV.to_h) # rubocop:disable Lint/UnusedMethodArgument
            options, positional = parse_options(argv)
            id = positional[0]
            unless id
              return JsonPrinter.failure(stderr, code: :invalid_arguments,
                                                 message: 'ID positional argument is required.')
            end

            root = TaskSupport.resolve_root(options[:root], cwd, stderr: stderr)
            return root if root.is_a?(Integer)

            result = Owl::Artifacts::Api.find(root: root, key: id)
            return JsonPrinter.failure(stderr, **TaskSupport.error_payload(result)) if result.err?

            payload = result.value
            out = { ok: true, id: payload[:type] }
            paths = Owl::Artifacts::Api.local_paths(root: root, key: id)
            if paths.ok?
              out[:source_path] = paths.value.source_path
              out[:template_path] = paths.value.template_path
            end
            out[:template_present] = payload[:template_present]
            out[:definition] = payload[:body]
            out[:validation] = payload[:validation]
            out[:front_matter] = payload[:front_matter]
            JsonPrinter.success(stdout, out)
          rescue OptionParser::ParseError => e
            JsonPrinter.failure(stderr, code: :invalid_arguments, message: e.message)
          end

          def parse_options(argv)
            options = { root: nil }
            parser = OptionParser.new do |opts|
              opts.banner = 'Usage: owl artifact-type show ID [--root PATH] [--json]'
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
