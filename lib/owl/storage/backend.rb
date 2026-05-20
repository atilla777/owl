# frozen_string_literal: true

module Owl
  module Storage
    class UnknownBackendError < StandardError; end

    # Public contract for an Owl storage backend.
    #
    # Filesystem is the v1 implementation (see Backends::Filesystem). Future backends
    # (e.g. remote HTTP, SQLite) implement the same instance methods. A backend is
    # constructed for a specific repository root and exposes path-level storage
    # operations without repeating the root in every call.
    #
    # Layer-C bootstrap exception: `detect_root(start:)` is declared on this
    # interface for symmetry, but it must operate without depending on `@root` —
    # the whole point of `detect_root` is to find a project root before any
    # backend can be selected. Implementations therefore ignore the bound root
    # and walk the filesystem (or equivalent) using only `start`. The facade
    # `Owl::Storage::Api.detect_root` calls `detect_root` on a default filesystem
    # backend constructed with `root: nil`, bypassing `BackendResolver` so the
    # bootstrap chicken-and-egg between "what is the project root?" and "what
    # backend serves that project?" is resolved.
    module Backend
      def read(path:)
        raise NotImplementedError
      end

      def write(path:, contents:)
        raise NotImplementedError
      end

      def mkdir_p(path:)
        raise NotImplementedError
      end

      def exists?(path:)
        raise NotImplementedError
      end

      def resolve(role:, profile:, vars: {})
        raise NotImplementedError
      end

      def detect_root(start:)
        raise NotImplementedError
      end
    end
  end
end
