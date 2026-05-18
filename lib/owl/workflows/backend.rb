# frozen_string_literal: true

module Owl
  module Workflows
    class UnknownBackendError < StandardError; end

    # Public contract for an Owl workflows backend.
    #
    # Filesystem is the v1 implementation (see Backends::Filesystem). Future backends
    # (e.g. Obsidian, SQLite) implement the same instance methods. A workflows backend
    # is responsible for resolving artefacts that live alongside a workflow source — at
    # present, per-step context Markdown files referenced via `step.context_file`.
    module Backend
      def read_step_context(source_dir:, step_id:, relative_path:)
        raise NotImplementedError
      end
    end
  end
end
