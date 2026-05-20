# frozen_string_literal: true

module Owl
  module Artifacts
    class UnknownBackendError < StandardError; end

    # Public contract for an Owl artifacts backend.
    #
    # Filesystem is the v1 implementation (see Backends::Filesystem). Future
    # backends (e.g. SQLite, remote HTTP) implement the same instance methods.
    # A backend is constructed for a specific repository root and exposes the
    # full surface of artifact-type operations: registry inspection, list,
    # find, per-task artifact resolution, scaffolding of new artifact-type
    # sources, validation of an artifact-type definition, and the seed
    # material used by `owl init`.
    module Backend
      def registry
        raise NotImplementedError
      end

      def list
        raise NotImplementedError
      end

      def find(key:)
        raise NotImplementedError
      end

      def resolve(task_id:, artifact_key:)
        raise NotImplementedError
      end

      def scaffold(id:, body: nil, force: false)
        raise NotImplementedError
      end

      def validate(id_or_path:)
        raise NotImplementedError
      end

      def default_template
        raise NotImplementedError
      end

      def seeded_sources
        raise NotImplementedError
      end
    end
  end
end
