# frozen_string_literal: true

require 'optparse'

require_relative '../../../recall/api'
require_relative '../json_printer'
require_relative 'task_support'

module Owl
  module Cli
    module Internal
      module Commands
        # `owl recall <query> [--limit N] [--root PATH] [--json|--no-json]`
        #
        # Read-only cross-task memory: ranks similar archived tasks by
        # lexical match and emits `{ ok: true, matches: [...] }`. A trivial
        # query (empty / stopword-only) or no matches yields
        # `{ ok: true, matches: [] }` with exit 0 — it never crashes.
        module Recall
          module_function

          def run(argv:, stdout:, stderr:, cwd:, env: ENV.to_h) # rubocop:disable Lint/UnusedMethodArgument
            options, positional = parse_options(argv)
            root = TaskSupport.resolve_root(options[:root], cwd, stderr: stderr)
            return root if root.is_a?(Integer)

            query = positional.join(' ').strip
            matches = Owl::Recall::Api.recall(root: root, query: query, limit: options[:limit])
            emit(stdout, options, matches)
          rescue OptionParser::ParseError => e
            JsonPrinter.failure(stderr, code: :invalid_arguments, message: e.message)
          end

          def emit(stdout, options, matches)
            payload = matches.map do |match|
              { task_id: match[:task_id], title: match[:title], score: match[:score], snippet: match[:snippet] }
            end
            return JsonPrinter.success(stdout, { ok: true, matches: payload }) if options[:json]

            print_human(stdout, payload)
          end

          def print_human(stdout, matches)
            if matches.empty?
              stdout.puts('No similar archived tasks found.')
            else
              matches.each do |match|
                stdout.puts("#{match[:task_id]}  #{match[:title]}  (score #{match[:score]})")
                stdout.puts("  #{match[:snippet]}")
              end
            end
            0
          end

          def parse_options(argv)
            options = { root: nil, json: true, limit: Owl::Recall::Api::DEFAULT_LIMIT }
            parser = OptionParser.new do |opts|
              opts.banner = 'Usage: owl recall <query> [--limit N] [--root PATH] [--json|--no-json]'
              opts.on('--limit N', Integer) { |v| options[:limit] = v }
              opts.on('--root PATH', String) { |v| options[:root] = v }
              opts.on('--[no-]json', 'Emit JSON (default) or a plain-text list') { |v| options[:json] = v }
            end
            positional = parser.parse(argv)
            [options, positional]
          end
        end
      end
    end
  end
end
