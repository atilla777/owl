# frozen_string_literal: true

require 'optparse'

require_relative '../../../upgrade/api'
require_relative '../json_printer'
require_relative 'task_support'

module Owl
  module Cli
    module Internal
      module Commands
        # `owl upgrade` — provenance-aware refresh of the current project's copied
        # Owl seed content after a gem update. Preserves project-owned content
        # (overlays, tasks, config edits, managed:false clones). `--dry-run`
        # previews; backups land in .owl/.backup/<ts>/ unless `--no-backup`.
        module Upgrade
          module_function

          def run(argv:, stdout:, stderr:, cwd:, env: ENV.to_h) # rubocop:disable Lint/UnusedMethodArgument
            options = parse_options(argv)
            root = TaskSupport.resolve_root(options[:root], cwd, stderr: stderr)
            return root if root.is_a?(Integer)

            result = Owl::Upgrade::Api.refresh(
              root: root, dry_run: options[:dry_run], backup: options[:backup]
            )
            return JsonPrinter.failure(stderr, **TaskSupport.error_payload(result)) if result.err?

            JsonPrinter.success(stdout, { ok: true }.merge(result.value))
          rescue OptionParser::ParseError => e
            JsonPrinter.failure(stderr, code: :invalid_arguments, message: e.message)
          end

          def parse_options(argv)
            options = { root: nil, dry_run: false, backup: true }
            parser = OptionParser.new do |opts|
              opts.banner = 'Usage: owl upgrade [--dry-run] [--no-backup] [--root PATH] [--json]'
              opts.on('--dry-run', 'Show what would change without writing') { options[:dry_run] = true }
              opts.on('--no-backup', 'Do not copy replaced files into .owl/.backup/') { options[:backup] = false }
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
