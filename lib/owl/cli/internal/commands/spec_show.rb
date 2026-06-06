# frozen_string_literal: true

require 'optparse'

require_relative '../../../specs/api'
require_relative '../json_printer'
require_relative 'task_support'

module Owl
  module Cli
    module Internal
      module Commands
        module SpecShow
          module_function

          def run(argv:, stdout:, stderr:, cwd:, env: ENV.to_h) # rubocop:disable Lint/UnusedMethodArgument
            options, positional = parse_options(argv)
            domain = positional.first
            unless domain
              return JsonPrinter.failure(
                stderr,
                code: :invalid_arguments,
                message: 'DOMAIN positional argument is required.'
              )
            end

            root = TaskSupport.resolve_root(options[:root], cwd, stderr: stderr)
            return root if root.is_a?(Integer)

            result = Owl::Specs::Api.show(root: root, domain: domain)
            return JsonPrinter.failure(stderr, **TaskSupport.error_payload(result)) if result.err?

            return print_body(stdout, result.value[:body]) unless options[:json]

            JsonPrinter.success(stdout, {
                                  ok: true,
                                  domain: result.value[:domain],
                                  path: result.value[:path],
                                  body: result.value[:body]
                                })
          rescue OptionParser::ParseError => e
            JsonPrinter.failure(stderr, code: :invalid_arguments, message: e.message)
          end

          def print_body(stdout, body)
            stdout.print(body)
            0
          end

          def parse_options(argv)
            options = { root: nil, json: true }
            parser = OptionParser.new do |opts|
              opts.banner = 'Usage: owl spec show DOMAIN [--root PATH] [--json|--no-json]'
              opts.on('--root PATH', String) { |v| options[:root] = v }
              opts.on('--[no-]json', 'Emit JSON (default) or print the raw spec body') { |v| options[:json] = v }
            end
            positional = parser.parse(argv)
            [options, positional]
          end
        end
      end
    end
  end
end
