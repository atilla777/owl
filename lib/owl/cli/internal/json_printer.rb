# frozen_string_literal: true

require 'json'

module Owl
  module Cli
    module Internal
      module JsonPrinter
        module_function

        def success(stdout, payload)
          stdout.puts(JSON.generate(payload))
          0
        end

        def failure(stderr, code:, message:, details: {})
          body = {
            ok: false,
            error: { code: code.to_s, message: message, details: details }
          }
          stderr.puts(JSON.generate(body))
          1
        end
      end
    end
  end
end
