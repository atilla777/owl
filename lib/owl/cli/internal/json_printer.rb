# frozen_string_literal: true

require 'json'

module Owl
  module Cli
    module Internal
      # JSON-payload printer for the env-agnostic CLI contract.
      #
      # Failures carry both a specific `code` (e.g. `'drift_block'`) and a
      # broad `error_class` that maps deterministically to the process exit
      # code via EXIT_CODES. Orchestrator scripts read either source: the
      # exit code for a fast branch and the JSON payload for full detail
      # (RFC #1 §4.6).
      #
      # Exit codes:
      #   1  validation               — workflow / artifact / argument schema or shape error
      #   2  recoverable              — drift, lock, retryable runtime condition
      #   3  fatal                    — unrecoverable runtime (missing gem assets, etc.)
      #   4  step_context_frontmatter — `.context.md` frontmatter contract violation (KOS-156)
      module JsonPrinter
        EXIT_CODES = {
          validation: 1,
          recoverable: 2,
          fatal: 3,
          step_context_frontmatter: 4
        }.freeze

        module_function

        def success(stdout, payload)
          stdout.puts(JSON.generate(payload))
          0
        end

        def failure(stderr, code:, message:, details: {}, error_class: :validation)
          unless EXIT_CODES.key?(error_class)
            raise ArgumentError,
                  "Unknown error_class #{error_class.inspect}; allowed: #{EXIT_CODES.keys.inspect}"
          end

          body = {
            ok: false,
            error: {
              code: code.to_s,
              message: message,
              error_class: error_class.to_s,
              details: details
            }
          }
          stderr.puts(JSON.generate(body))
          EXIT_CODES.fetch(error_class)
        end
      end
    end
  end
end
