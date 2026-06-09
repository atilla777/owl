# frozen_string_literal: true

require 'optparse'

require_relative '../../../locks/api'
require_relative '../json_printer'
require_relative 'task_support'

module Owl
  module Cli
    module Internal
      module Commands
        # `owl git unlock --token T` — release the repo-scoped git lock. The
        # token must match the holder, otherwise `lock_not_owned`.
        module GitUnlock
          module_function

          DEFAULT_NAME = 'git'

          def run(argv:, stdout:, stderr:, cwd:, env: ENV.to_h) # rubocop:disable Lint/UnusedMethodArgument
            options = parse_options(argv)
            unless options[:token]
              return JsonPrinter.failure(stderr, code: :invalid_arguments, message: '--token is required.')
            end

            root = TaskSupport.resolve_root(options[:root], cwd, stderr: stderr)
            return root if root.is_a?(Integer)

            result = Owl::Locks::Api.release(root: root, name: options[:name], token: options[:token])
            return JsonPrinter.failure(stderr, **TaskSupport.error_payload(result)) if result.err?

            JsonPrinter.success(stdout, { ok: true, name: result.value[:name], released: result.value[:released] })
          rescue OptionParser::ParseError => e
            JsonPrinter.failure(stderr, code: :invalid_arguments, message: e.message)
          end

          def parse_options(argv)
            options = { root: nil, name: DEFAULT_NAME, token: nil }
            parser = OptionParser.new do |opts|
              opts.banner = 'Usage: owl git unlock --token T [--name N] [--root PATH] [--json]'
              opts.on('--token T', String) { |v| options[:token] = v }
              opts.on('--name N', String) { |v| options[:name] = v }
              opts.on('--root PATH', String) { |v| options[:root] = v }
              opts.on('--json', 'Force JSON output (default)') { options[:json] = true }
            end
            parser.parse(argv)
            options
          end
        end
      end
    end
  end
end
