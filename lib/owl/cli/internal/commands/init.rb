# frozen_string_literal: true

require 'optparse'
require 'pathname'

require_relative '../../../artifacts/api'
require_relative '../../../config/api'
require_relative '../../../storage/api'
require_relative '../../../workflows/api'
require_relative '../json_printer'

module Owl
  module Cli
    module Internal
      module Commands
        module Init
          module_function

          def run(argv:, stdout:, stderr:, cwd:, env: ENV.to_h) # rubocop:disable Lint/UnusedMethodArgument
            options = parse_options(argv)
            root = Pathname.new(options[:root] || cwd).expand_path
            force = options[:force]

            files = layout_files(root: root, project_id: derive_project_id(root))

            created = []
            skipped = []

            files.each do |file|
              path = Pathname.new(file[:path])
              if path.exist? && !force
                skipped << path.to_s
                next
              end

              path.dirname.mkpath
              path.write(file[:contents])
              created << path.to_s
            end

            JsonPrinter.success(stdout, {
                                  ok: true,
                                  root: root.to_s,
                                  created: created,
                                  skipped: skipped
                                })
          rescue OptionParser::ParseError => e
            JsonPrinter.failure(stderr, code: :invalid_arguments, message: e.message)
          end

          def parse_options(argv)
            options = { root: nil, force: false }
            parser = OptionParser.new do |opts|
              opts.banner = 'Usage: owl init [--root PATH] [--force]'
              opts.on('--root PATH', String, 'Project root (default: cwd)') { |v| options[:root] = v }
              opts.on('--force', 'Overwrite existing files') { options[:force] = true }
              opts.on('--json', 'Force JSON output (default)') { options[:json] = true }
            end
            parser.parse!(argv)
            options
          end

          def derive_project_id(root)
            root.basename.to_s
          end

          def layout_files(root:, project_id:)
            [
              { path: "#{root}/.owl/config.yaml",
                contents: Owl::Config::Api.default_template(project_id: project_id) },
              { path: "#{root}/.owl/workflows.yaml",
                contents: Owl::Workflows::Api.default_template },
              { path: "#{root}/.owl/artifacts.yaml",
                contents: Owl::Artifacts::Api.default_template },
              { path: "#{root}/tasks/index.yaml",
                contents: tasks_index_template },
              { path: "#{root}/docs/.keep",
                contents: '' }
            ]
          end

          def tasks_index_template
            <<~YAML
              schema_version: 1

              tasks: []
            YAML
          end
        end
      end
    end
  end
end
