# frozen_string_literal: true

require 'optparse'

require_relative '../../../upgrade/api'
require_relative '../json_printer'

module Owl
  module Cli
    module Internal
      module Commands
        # `owl self-update` — update the owl-cli gem itself from github main
        # (clone → gem build → gem install). `--check` only compares versions.
        # After updating, run `owl upgrade` in each project to refresh its copies.
        module SelfUpdate
          module_function

          def run(argv:, stdout:, stderr:, cwd:, env: ENV.to_h) # rubocop:disable Lint/UnusedMethodArgument
            options = parse_options(argv)

            result = Owl::Upgrade::Api.self_update(check: options[:check])
            if result.err?
              return JsonPrinter.failure(stderr, code: result.code, message: result.message,
                                                 details: result.details)
            end

            payload = { ok: true }.merge(result.value)
            if result.value[:action] == 'installed'
              payload[:hint] = 'Run `owl upgrade` in each project to refresh its copied seed files.'
            end
            JsonPrinter.success(stdout, payload)
          rescue OptionParser::ParseError => e
            JsonPrinter.failure(stderr, code: :invalid_arguments, message: e.message)
          end

          def parse_options(argv)
            options = { check: false }
            parser = OptionParser.new do |opts|
              opts.banner = 'Usage: owl self-update [--check] [--json]'
              opts.on('--check', 'Compare installed version with main without installing') { options[:check] = true }
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
