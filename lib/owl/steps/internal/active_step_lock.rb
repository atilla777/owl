# frozen_string_literal: true

require 'pathname'
require 'time'
require 'yaml'

require_relative '../../result'
require_relative '../../storage/api'

module Owl
  module Steps
    module Internal
      # Active step lock — persistent record of a currently-executing step.
      # Created by `owl step start`, cleared by `owl step complete`.
      #
      # Per-task: each task gets its own lock at
      # `.owl/local/active_steps/<TASK-ID>.yaml`, so two different tasks may
      # each hold a running step at the same time (one running step *per
      # task*, not per repo). Format:
      #
      #     schema_version: 1
      #     task_id: TASK-1
      #     step_id: implement
      #     session_type: execution
      #     declared_at: 2026-05-24T10:30:00Z
      #     variant: ~                # optional
      #
      # Enforces the session_type contract from RFC #1 §2: when present, the
      # lock is the authoritative source of session_type for that task's
      # running step. `owl step report` cross-checks report frontmatter
      # against the lock and rejects on mismatch (recoverable error).
      module ActiveStepLock
        SCHEMA_VERSION = 1
        RELATIVE_DIR = '.owl/local/active_steps'

        module_function

        def dir(root:)
          Pathname.new(root.to_s) + RELATIVE_DIR
        end

        def path(root:, task_id:)
          dir(root: root) + "#{task_id}.yaml"
        end

        # Per-task load. Returns Result.ok(nil) when no lock exists for the
        # task, Result.ok(payload Hash) when valid, Result.err otherwise.
        def load(root:, task_id:)
          load_path(path(root: root, task_id: task_id))
        end

        # Resolve the sole repo-wide lock for id inference. Returns
        # Result.ok(payload) only when exactly one task holds a lock;
        # Result.ok(nil) when zero or more than one do (ambiguous → caller
        # falls through); Result.err when the single lock is malformed.
        def load_sole(root:)
          files = lock_files(root: root)
          return Result.ok(nil) unless files.size == 1

          load_path(files.first)
        end

        def write(root:, task_id:, step_id:, session_type:, variant: nil)
          lock_path = path(root: root, task_id: task_id)
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

        def clear(root:, task_id:)
          lock_path = path(root: root, task_id: task_id)
          return Result.ok(:absent) unless Owl::Storage::Api.exists?(path: lock_path)

          File.delete(lock_path.to_s)
          Result.ok(:cleared)
        end

        # Convenience: returns true when the lock describes the given step.
        def matches?(payload, task_id:, step_id:)
          return false unless payload.is_a?(Hash)

          payload['task_id'].to_s == task_id.to_s && payload['step_id'].to_s == step_id.to_s
        end

        def load_path(lock_path)
          return Result.ok(nil) unless Owl::Storage::Api.exists?(path: lock_path)

          read = Owl::Storage::Api.read(path: lock_path)
          return read if read.err?

          payload = YAML.safe_load(read.value, permitted_classes: [], permitted_symbols: [])
          return Result.ok(payload) if payload.is_a?(Hash)

          Result.err(
            code: :active_step_lock_invalid,
            message: "Active-step lock at #{lock_path} is not a YAML mapping."
          )
        rescue Psych::SyntaxError => e
          Result.err(
            code: :active_step_lock_invalid,
            message: "Active-step lock YAML is invalid: #{e.message}"
          )
        end

        def lock_files(root:)
          listing = Owl::Storage::Api.children(path: dir(root: root))
          children = listing.respond_to?(:value) ? Array(listing.value) : Array(listing)
          children.select { |child| child.file? && child.extname == '.yaml' }
                  .sort_by(&:to_s)
        end
      end
    end
  end
end
