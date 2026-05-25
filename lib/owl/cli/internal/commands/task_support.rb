# frozen_string_literal: true

require 'pathname'

require_relative '../../../storage/api'
require_relative '../json_printer'

module Owl
  module Cli
    module Internal
      module Commands
        module TaskSupport
          module_function

          def resolve_root(explicit_root, cwd, stderr:)
            if explicit_root
              Pathname.new(explicit_root).expand_path
            else
              detect = Owl::Storage::Api.detect_root(start: cwd)
              return JsonPrinter.failure(stderr, **error_payload(detect)) if detect.err?

              detect.value
            end
          end

          def error_payload(err_result)
            payload = { code: err_result.code, message: err_result.message, details: err_result.details }
            if err_result.respond_to?(:error_class) && err_result.error_class
              payload[:error_class] =
                err_result.error_class
            end
            payload
          end
        end
      end
    end
  end
end
