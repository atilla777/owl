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
              step_variants: options[:step_variants],
              priority: options[:priority]
            )

            return JsonPrinter.failure(stderr, **TaskSupport.error_payload(result)) if result.err?

            JsonPrinter.success(stdout, success_payload(root: root, result: result))
          rescue OptionParser::ParseError => e
            JsonPrinter.failure(stderr, code: :invalid_arguments, message: e.message)
          end

          def success_payload(root:, result:)
            payload = { ok: true, task: result.value[:payload] }
            paths = Owl::Tasks::Api.local_paths(root: root, task_id: result.value[:task_id])
            if paths.ok?
              payload[:task_path] = paths.value[:task_file].task_path
              payload[:index_path] = paths.value[:index].index_path
            end
            payload
          end

          def parse_options(argv)
            options = { root: nil, workflow: nil, title: nil, parent_id: nil, kind: nil, step_variants: {},
                        priority: 0 }
            parser = OptionParser.new do |opts|
              opts.banner = 'Usage: owl task create --workflow KEY --title TITLE ' \
                            '[--parent TASK-ID] [--kind KIND] [--variant STEP=NAME] [--priority N] ' \
                            '[--root PATH] [--json]'
              opts.on('--workflow KEY', String) { |v| options[:workflow] = v }
              opts.on('--title TITLE', String) { |v| options[:title] = v }
              opts.on('--parent TASK-ID', String) { |v| options[:parent_id] = v }
              opts.on('--kind KIND', String) { |v| options[:kind] = v }
              opts.on('--priority N', Integer) { |v| options[:priority] = v }
              opts.on('--variant STEP=NAME', String) { |v| add_variant(options, v) }
              opts.on('--root PATH', String) { |v| options[:root] = v }
              opts.on('--json', 'Force JSON output (default)') { options[:json] = true }
            end
            parser.parse!(argv)
            options
          end

          def add_variant(options, value)
            step, name = value.split('=', 2)
            if step.nil? || step.strip.empty? || name.nil? || name.strip.empty?
              raise OptionParser::ParseError, "--variant expects STEP=NAME, got #{value.inspect}"
            end

            options[:step_variants][step.strip] = name.strip
          end
        end
      end
    end
  end
end
