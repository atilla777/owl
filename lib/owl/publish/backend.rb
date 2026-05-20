# frozen_string_literal: true

module Owl
  module Publish
    class UnknownBackendError < StandardError; end

    # Public contract for an Owl publish backend.
    #
    # Filesystem is the v1 implementation (see Backends::Filesystem). Future
    # backends (e.g. SQLite, remote HTTP) implement the same instance methods.
    # A backend is constructed for a specific repository root and exposes the
    # single `run` operation that publishes a task's artifacts to their target
    # storage locations per the workflow's `publishes:` rules.
    #
    # Backup-on-replace semantics (e.g. the `.bak.<timestamp>` suffix produced
    # by `Backends::Filesystem`) are intentionally backend-defined: the contract
    # only promises that `run` returns per-rule results including a string
    # `backup_path` when an existing target was replaced, or `nil` otherwise.
    # A non-filesystem backend may persist prior versions through a column,
    # versioning header, content-addressed key, etc., and may return `nil` for
    # `backup_path` even on replace.
    module Backend
      def run(task_id:, dry_run: false, now: Time.now.utc)
        raise NotImplementedError
      end
    end
  end
end
