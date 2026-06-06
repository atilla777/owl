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

          # Pure path-math: expand a user-supplied relative path against the
          # CLI's `cwd` (not the process pwd). No I/O — kept here because this
          # file is on the constitution's path-utility allowlist.
          def expand_path(path, cwd)
            Pathname.new(path).expand_path(cwd).to_s
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
