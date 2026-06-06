# frozen_string_literal: true

require 'optparse'

require_relative '../../../specs/api'
require_relative '../json_printer'
require_relative 'task_support'

module Owl
  module Cli
    module Internal
      module Commands
        # `owl spec trace DOMAIN [--strict] [--json|--no-json]` — read-only
        # requirement -> scenario -> test coverage report. JSON (default) emits
        # the full report; `--no-json` prints an ordered readable summary. The
        # process exit code follows `ok` (0 when ok, 1 otherwise), so under
        # `--strict` an untraced/dangling spec exits non-zero.
        module SpecTrace
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

            result = Owl::Specs::Api.trace(root: root, domain: domain, strict: options[:strict])
            return JsonPrinter.failure(stderr, **TaskSupport.error_payload(result)) if result.err?

            emit(stdout, result.value, json: options[:json])
          rescue OptionParser::ParseError => e
            JsonPrinter.failure(stderr, code: :invalid_arguments, message: e.message)
          end

          def emit(stdout, report, json:)
            return emit_summary(stdout, report) unless json

            stdout.puts(JSON.generate(json_payload(report)))
            report[:ok] ? 0 : 1
          end

          def json_payload(report)
            {
              ok: report[:ok],
              valid: report[:valid],
              domain: report[:domain],
              path: report[:path],
              summary: report[:summary],
              requirements: report[:requirements],
              untraced: report[:untraced],
              dangling: report[:dangling],
              unverified: report[:unverified]
            }
          end

          def emit_summary(stdout, report)
            stdout.puts("spec #{report[:domain]} (#{report[:path]})")
            stdout.puts(summary_line(report[:summary]))
            report[:requirements].each { |requirement| print_requirement(stdout, requirement) }
            stdout.puts("valid: #{report[:valid]}")
            report[:ok] ? 0 : 1
          end

          def summary_line(summary)
            format(
              'requirements: %<requirements>d  scenarios: %<scenarios>d  traced: %<traced>d  ' \
              'untraced: %<untraced>d  dangling: %<dangling>d  unverified: %<unverified>d',
              summary
            )
          end

          def print_requirement(stdout, requirement)
            stdout.puts("  Requirement: #{requirement[:name]}")
            requirement[:scenarios].each do |scenario|
              refs = scenario[:test_refs].empty? ? '(no TEST)' : scenario[:test_refs].join(', ')
              stdout.puts("    Scenario: #{scenario[:name]} — #{scenario[:status]} [#{refs}]")
            end
          end

          def parse_options(argv)
            options = { root: nil, json: true, strict: false }
            parser = OptionParser.new do |opts|
              opts.banner = 'Usage: owl spec trace DOMAIN [--strict] [--root PATH] [--json|--no-json]'
              opts.on('--root PATH', String) { |v| options[:root] = v }
              opts.on('--strict', 'Flip ok:false (exit 1) on any untraced scenario or dangling ref') do
                options[:strict] = true
              end
              opts.on('--[no-]json', 'Emit JSON (default) or a readable summary') { |v| options[:json] = v }
            end
            positional = parser.parse(argv)
            [options, positional]
          end
        end
      end
    end
  end
end
