# frozen_string_literal: true

require 'optparse'

require_relative '../../../specs/api'
require_relative '../json_printer'
require_relative 'task_support'

module Owl
  module Cli
    module Internal
      module Commands
        # `owl spec apply DOMAIN --delta PATH [--dry-run]` — apply a structural
        # delta to the domain spec. Writes the merged spec on success; `--dry-run`
        # previews without writing.
        module SpecApply
          module_function

          def run(argv:, stdout:, stderr:, cwd:, env: ENV.to_h) # rubocop:disable Lint/UnusedMethodArgument
            options, positional = parse_options(argv)
            domain = positional.first
            return missing_domain(stderr) unless domain
            return missing_delta(stderr) unless options[:delta]

            root = TaskSupport.resolve_root(options[:root], cwd, stderr: stderr)
            return root if root.is_a?(Integer)

            result = Owl::Specs::Api.apply(
              root: root, domain: domain, delta_path: TaskSupport.expand_path(options[:delta], cwd),
              dry_run: options[:dry_run]
            )
            return JsonPrinter.failure(stderr, **TaskSupport.error_payload(result)) if result.err?

            emit(stdout, result.value)
          rescue OptionParser::ParseError => e
            JsonPrinter.failure(stderr, code: :invalid_arguments, message: e.message)
          end

          def emit(stdout, value)
            JsonPrinter.success(stdout, {
                                  ok: true,
                                  domain: value[:domain],
                                  path: value[:path],
                                  created: value[:created],
                                  dry_run: value[:dry_run],
                                  applied: value[:applied],
                                  unified_diff: value[:unified_diff]
                                })
          end

          def missing_domain(stderr)
            JsonPrinter.failure(stderr, code: :invalid_arguments, message: 'DOMAIN positional argument is required.')
          end

          def missing_delta(stderr)
            JsonPrinter.failure(stderr, code: :invalid_arguments, message: '--delta PATH is required.')
          end

          def parse_options(argv)
            options = { root: nil, delta: nil, dry_run: false }
            parser = OptionParser.new do |opts|
              opts.banner = 'Usage: owl spec apply DOMAIN --delta PATH [--dry-run] [--root PATH] [--json]'
              opts.on('--delta PATH', String) { |v| options[:delta] = v }
              opts.on('--dry-run', 'Preview the merge without writing') { options[:dry_run] = true }
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
