# frozen_string_literal: true

require 'pathname'
require 'time'
require 'yaml'

require_relative '../../result'
require_relative '../../storage/api'

module Owl
  module Steps
    module Internal
      # Active step lock — persistent record of the currently-executing step.
      # Created by `owl step start`, cleared by `owl step complete`.
      # Lives at `.owl/local/active_step.yaml`. Format:
      #
      #     schema_version: 1
      #     task_id: TASK-1
      #     step_id: implement
      #     session_type: execution
      #     declared_at: 2026-05-24T10:30:00Z
      #     variant: ~                # optional
      #
      # Enforces session_type contract from RFC #1 §2: when present, the
      # lock is the authoritative source of session_type for the currently
      # running step. `owl step report` cross-checks the report frontmatter
      # against the lock and rejects on mismatch (recoverable error).
      module ActiveStepLock
        SCHEMA_VERSION = 1
        RELATIVE_PATH = '.owl/local/active_step.yaml'

        module_function

        def path(root:)
          Pathname.new(root.to_s) + RELATIVE_PATH
        end

        # Returns Result.ok(nil) when no lock exists,
        # Result.ok(payload Hash) when valid,
        # Result.err otherwise.
        def load(root:)
          lock_path = path(root: root)
          return Result.ok(nil) unless Owl::Storage::Api.exists?(path: lock_path)

          read = Owl::Storage::Api.read(path: lock_path)
          return read if read.err?

          payload = YAML.safe_load(read.value, permitted_classes: [], permitted_symbols: [])
          unless payload.is_a?(Hash)
            return Result.err(
              code: :active_step_lock_invalid,
              message: "Active-step lock at #{lock_path} is not a YAML mapping."
            )
          end

          Result.ok(payload)
        rescue Psych::SyntaxError => e
          Result.err(
            code: :active_step_lock_invalid,
            message: "Active-step lock YAML is invalid: #{e.message}"
          )
        end

        def write(root:, task_id:, step_id:, session_type:, variant: nil)
          lock_path = path(root: root)
          payload = {
            'schema_version' => SCHEMA_VERSION,
            'task_id' => task_id.to_s,
            'step_id' => step_id.to_s,
            'session_type' => session_type.to_s,
            'declared_at' => Time.now.utc.iso8601
          }
          payload['variant'] = variant.to_s if variant

          Owl::Storage::Api.mkdir_p(path: lock_path.dirname)
          Owl::Storage::Api.write(path: lock_path, contents: payload.to_yaml)
        end

        def clear(root:)
          lock_path = path(root: root)
          return Result.ok(:absent) unless Owl::Storage::Api.exists?(path: lock_path)

          File.delete(lock_path.to_s)
          Result.ok(:cleared)
        end

        # Convenience: returns true when the lock describes the given step.
        def matches?(payload, task_id:, step_id:)
          return false unless payload.is_a?(Hash)

          payload['task_id'].to_s == task_id.to_s && payload['step_id'].to_s == step_id.to_s
        end
      end
    end
  end
end
