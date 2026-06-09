# frozen_string_literal: true

require 'optparse'

require_relative '../../../locks/api'
require_relative '../json_printer'
require_relative 'task_support'

module Owl
  module Cli
    module Internal
      module Commands
        # `owl git lock` — acquire the repo-scoped lock that serializes pushes
        # to `main` from the `commit_push` step. Returns a `token` to pass to
        # `owl git unlock`. A live lock yields `lock_held` (recoverable, exit 2).
        module GitLock
          module_function

          DEFAULT_NAME = 'git'

          def run(argv:, stdout:, stderr:, cwd:, env: ENV.to_h) # rubocop:disable Lint/UnusedMethodArgument
            options = parse_options(argv)
            root = TaskSupport.resolve_root(options[:root], cwd, stderr: stderr)
            return root if root.is_a?(Integer)

            result = Owl::Locks::Api.acquire(
              root: root, name: options[:name], ttl: options[:ttl], steal: options[:steal]
            )
            return JsonPrinter.failure(stderr, **TaskSupport.error_payload(result)) if result.err?

            JsonPrinter.success(stdout, {
                                  ok: true,
                                  name: result.value[:name],
                                  token: result.value[:token],
                                  expires_at: result.value[:expires_at],
                                  ttl_seconds: result.value[:ttl_seconds]
                                })
          rescue OptionParser::ParseError => e
            JsonPrinter.failure(stderr, code: :invalid_arguments, message: e.message)
          end

          def parse_options(argv)
            options = { root: nil, name: DEFAULT_NAME, ttl: nil, steal: false }
            parser = OptionParser.new do |opts|
              opts.banner = 'Usage: owl git lock [--name N] [--ttl N] [--steal] [--root PATH] [--json]'
              opts.on('--name N', String) { |v| options[:name] = v }
              opts.on('--ttl N', Integer) { |v| options[:ttl] = v }
              opts.on('--steal', 'Forcibly take over an existing lock') { options[:steal] = true }
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
