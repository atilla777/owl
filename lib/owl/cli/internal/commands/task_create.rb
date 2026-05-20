# frozen_string_literal: true

require 'optparse'

require_relative '../../../tasks/api'
require_relative '../json_printer'
require_relative 'task_support'

module Owl
  module Cli
    module Internal
      module Commands
        module TaskCreate
          module_function

          def run(argv:, stdout:, stderr:, cwd:, env: ENV.to_h) # rubocop:disable Lint/UnusedMethodArgument
            options = parse_options(argv)
            unless options[:workflow] && options[:title]
              return JsonPrinter.failure(
                stderr,
                code: :invalid_arguments,
                message: '--workflow and --title are required.'
              )
            end

            root = TaskSupport.resolve_root(options[:root], cwd, stderr: stderr)
            return root if root.is_a?(Integer)

            result = Owl::Tasks::Api.create(
              root: root,
              workflow: options[:workflow],
              title: options[:title],
              parent_id: options[:parent_id],
              kind: options[:kind],
              step_variants: options[:step_variants]
            )

            return JsonPrinter.failure(stderr, **TaskSupport.error_payload(result)) if result.err?

            JsonPrinter.success(stdout, {
                                  ok: true,
                                  task: result.value[:payload],
                                  task_path: result.value[:task_path],
                                  index_path: result.value[:index_path]
                                })
          rescue OptionParser::ParseError => e
            JsonPrinter.failure(stderr, code: :invalid_arguments, message: e.message)
          end

          def parse_options(argv)
            options = { root: nil, workflow: nil, title: nil, parent_id: nil, kind: nil, step_variants: {} }
            parser = OptionParser.new do |opts|
              opts.banner = 'Usage: owl task create --workflow KEY --title TITLE ' \
                            '[--parent TASK-ID] [--kind KIND] [--variant STEP=NAME] [--root PATH] [--json]'
              opts.on('--workflow KEY', String) { |v| options[:workflow] = v }
              opts.on('--title TITLE', String) { |v| options[:title] = v }
              opts.on('--parent TASK-ID', String) { |v| options[:parent_id] = v }
              opts.on('--kind KIND', String) { |v| options[:kind] = v }
              opts.on('--variant STEP=NAME', String) do |v|
                step, name = v.split('=', 2)
                if step.nil? || step.strip.empty? || name.nil? || name.strip.empty?
                  raise OptionParser::ParseError, "--variant expects STEP=NAME, got #{v.inspect}"
                end

                options[:step_variants][step.strip] = name.strip
              end
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
