# frozen_string_literal: true

module Owl
  module Validation
    class UnknownBackendError < StandardError; end

    # Public contract for an Owl validation backend.
    #
    # Filesystem is the v1 implementation (see Backends::Filesystem). Future
    # backends (e.g. SQLite, remote HTTP) implement the same instance methods.
    # A backend is constructed for a specific repository root and exposes two
    # operations: per-artifact validation (`artifact`) and full-task aggregate
    # validation across every workflow artifact (`task`).
    #
    # Result shapes are documented on each method below.
    module Backend
      # Validate a single workflow artifact for the given task.
      #
      # Returns Result.ok(artifact_key:, valid:, violations:, descriptor:)
      # on success and Result.err on resolution / lookup failures.
      def artifact(task_id:, artifact_key:)
        raise NotImplementedError
      end

      # Validate every workflow artifact declared by the task's workflow.
      #
      # Returns Result.ok(all_valid:, results:) where `results` is an array of
      # per-artifact result hashes (same shape as `artifact` value), and
      # Result.err on resolution / lookup failures.
      def task(task_id:)
        raise NotImplementedError
      end
    end
  end
end
