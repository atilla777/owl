# frozen_string_literal: true

require 'pathname'

require_relative '../../../storage/api'
require_relative '../../../tasks/api'
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

          # Guard shared by `next` / `ready-steps` / `status` / `instructions`:
          # when an EXPLICIT terminal task id is supplied, reject it with the
          # structured `task_terminal` code (non-zero exit) instead of pretending
          # the dead task is live. Returns the JsonPrinter failure exit code when
          # it fires, or `nil` to let the caller proceed.
          #
          # Applies ONLY to explicitly-passed ids: a `nil`/empty id (resolved
          # later from the current pointer) is left for the silent terminal
          # fallback in TaskResolver. A read Err (e.g. `task_not_found`) also
          # returns `nil` so the command's normal path surfaces that error.
          def reject_if_terminal(root:, task_id:, stderr:)
            return nil if task_id.nil? || task_id.to_s.empty?

            result = Owl::Tasks::Api.orchestration_terminal?(root: root, task_id: task_id)
            return nil if result.err? || !result.value

            JsonPrinter.failure(
              stderr,
              code: :task_terminal,
              message: "Task '#{task_id}' is terminal (archived/abandoned/done); it is not runnable.",
              details: { task_id: task_id.to_s }
            )
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
