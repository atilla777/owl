# frozen_string_literal: true

require 'optparse'

require_relative '../../../commit_push/api'
require_relative '../json_printer'
require_relative 'task_support'

module Owl
  module Cli
    module Internal
      module Commands
        # `owl commit-push TASK-ID --message M [--root PATH] [--json]`
        #
        # Atomically stage, flip `commit_push: done`, commit, pull --rebase and
        # push the terminal `commit_push` step as one transaction. `--message`
        # is required. Emits `{ ok: true, task_id, commit_sha, pushed }` on
        # success or `{ ok: false, error: { code, ... } }` on failure
        # (`push_retryable` keeps the local commit for an idempotent re-run).
        module CommitPush
          module_function

          def run(argv:, stdout:, stderr:, cwd:, env: ENV.to_h) # rubocop:disable Lint/UnusedMethodArgument
            options, positional = parse_options(argv)
            task_id = positional.first
            return JsonPrinter.failure(stderr, code: :invalid_arguments, message: 'TASK-ID is required.') unless task_id
            unless options[:message]
              return JsonPrinter.failure(stderr, code: :invalid_arguments, message: '--message is required.')
            end

            root = TaskSupport.resolve_root(options[:root], cwd, stderr: stderr)
            return root if root.is_a?(Integer)

            result = Owl::CommitPush::Api.commit_push(root: root, task_id: task_id, message: options[:message])
            return JsonPrinter.failure(stderr, **TaskSupport.error_payload(result)) if result.err?

            JsonPrinter.success(stdout, {
                                  ok: true,
                                  task_id: result.value[:task_id],
                                  commit_sha: result.value[:commit_sha],
                                  pushed: result.value[:pushed]
                                })
          rescue OptionParser::ParseError => e
            JsonPrinter.failure(stderr, code: :invalid_arguments, message: e.message)
          end

          def parse_options(argv)
            options = { root: nil, message: nil }
            parser = OptionParser.new do |opts|
              opts.banner = 'Usage: owl commit-push TASK-ID --message M [--root PATH] [--json]'
              opts.on('--message M', String) { |v| options[:message] = v }
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
