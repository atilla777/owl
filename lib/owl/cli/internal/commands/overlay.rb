# frozen_string_literal: true

require 'optparse'

require_relative '../../../context/api'
require_relative '../json_printer'
require_relative 'task_support'

module Owl
  module Cli
    module Internal
      module Commands
        # `owl overlay <list|show|validate> STEP-ID [--variant V]` — inspect which
        # context overlays resolve for a step, in resolution order. A debugging
        # surface over `Owl::Context::Api`, for workflow/overlay authors.
        module Overlay
          module_function

          def run(argv:, stdout:, stderr:, cwd:, env: ENV.to_h) # rubocop:disable Lint/UnusedMethodArgument
            sub = argv.first
            rest = argv.drop(1)
            case sub
            when 'list'     then list(argv: rest, stdout: stdout, stderr: stderr, cwd: cwd)
            when 'show'     then show(argv: rest, stdout: stdout, stderr: stderr, cwd: cwd)
            when 'validate' then validate(argv: rest, stdout: stdout, stderr: stderr, cwd: cwd)
            else
              JsonPrinter.failure(stderr, code: :unknown_command, message: "Unknown command: 'overlay #{sub}'.")
            end
          end

          def list(argv:, stdout:, stderr:, cwd:)
            options, step_id, root = prepare(argv, cwd, stderr)
            return step_id if step_id.is_a?(Integer)

            result = Owl::Context::Api.overlay_candidates(root: root, step_id: step_id, variant: options[:variant])
            JsonPrinter.success(stdout, ok: true, step_id: step_id, variant: options[:variant],
                                        candidates: result.value)
          rescue OptionParser::ParseError => e
            JsonPrinter.failure(stderr, code: :invalid_arguments, message: e.message)
          end

          def show(argv:, stdout:, stderr:, cwd:)
            options, step_id, root = prepare(argv, cwd, stderr)
            return step_id if step_id.is_a?(Integer)

            result = Owl::Context::Api.overlays_for(root: root, step_id: step_id, variant: options[:variant])
            JsonPrinter.success(stdout, ok: true, step_id: step_id, variant: options[:variant],
                                        overlays: result.value)
          rescue OptionParser::ParseError => e
            JsonPrinter.failure(stderr, code: :invalid_arguments, message: e.message)
          end

          def validate(argv:, stdout:, stderr:, cwd:)
            options, step_id, root = prepare(argv, cwd, stderr)
            return step_id if step_id.is_a?(Integer)

            overlays = Owl::Context::Api.overlays_for(root: root, step_id: step_id, variant: options[:variant]).value
            warnings = overlays.select { |o| o[:warning] }
                               .map { |o| { source: o[:source], warning: o[:warning].to_s } }
            JsonPrinter.success(stdout, ok: true, step_id: step_id, variant: options[:variant],
                                        applied: overlays.length, warnings: warnings)
          rescue OptionParser::ParseError => e
            JsonPrinter.failure(stderr, code: :invalid_arguments, message: e.message)
          end

          def prepare(argv, cwd, stderr)
            options = parse_options(argv)
            root = TaskSupport.resolve_root(options[:root], cwd, stderr: stderr)
            return [options, root, nil] if root.is_a?(Integer)

            step_id = options[:step] || argv.shift
            unless step_id
              return [options,
                      JsonPrinter.failure(stderr, code: :invalid_arguments, message: 'STEP-ID is required.'),
                      root]
            end

            [options, step_id, root]
          end

          def parse_options(argv)
            options = { step: nil, variant: nil, root: nil }
            parser = OptionParser.new do |opts|
              opts.banner = 'Usage: owl overlay <list|show|validate> STEP-ID [--variant V] [--root PATH] [--json]'
              opts.on('--variant V', String) { |v| options[:variant] = v }
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
