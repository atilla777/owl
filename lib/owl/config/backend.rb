# frozen_string_literal: true

module Owl
  module Config
    # Public contract for an Owl config backend.
    #
    # Filesystem is the v1 implementation (see Backends::Filesystem). Future
    # backends (e.g. remote HTTP, SQLite) implement the same instance methods.
    # A backend is constructed for a specific repository root and owns reads /
    # writes / validations against `.owl/config.yaml` (or its non-FS analogue).
    #
    # Backend instance methods are root-less — the project root is bound in the
    # constructor, mirroring `Owl::Storage::Backend` / `Owl::Workflows::Backend`
    # / `Owl::Tasks::Backend`. `Owl::Config::Api` re-exposes the same operations
    # as `(root:, ...)` keyword-driven facade methods and resolves the active
    # backend through `Owl::Internal::BackendResolver` with `scope: :config`.
    #
    # `default_template(project_id:)` is intentionally root-less in the contract
    # too: it renders the seeded `.owl/config.yaml` body before any project
    # exists, so the bound `@root` is unused (Layer-C exception #1 — same
    # pattern as `Owl::Workflows::Backend#default_template`). The facade calls
    # `default_template` on a default filesystem backend constructed with
    # `root: nil`, bypassing `BackendResolver`.
    module Backend
      def load
        raise NotImplementedError
      end

      def validate
        raise NotImplementedError
      end

      def read_key(key:)
        raise NotImplementedError
      end

      def write_key(key:, value:)
        raise NotImplementedError
      end

      def snapshot
        raise NotImplementedError
      end

      def default_template(project_id:)
        raise NotImplementedError
      end
    end
  end
end
