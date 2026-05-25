# frozen_string_literal: true

module Owl
  module Workflows
    class UnknownBackendError < StandardError; end

    # Public contract for an Owl workflows backend.
    #
    # Filesystem is the v1 implementation (see Backends::Filesystem). Future backends
    # (e.g. SQLite, remote HTTP) implement the same instance methods. A backend is
    # constructed for a specific repository root and exposes the full surface of
    # workflow operations: registry inspection, source lookup, scaffolding, validation,
    # graph and definition building, ready-step resolution, per-step context reading,
    # and the seed material used by `owl init`.
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

      def scaffold(id:, body: nil, kind: 'task', from: nil, force: false)
        raise NotImplementedError
      end

      def validate(id_or_path:)
        raise NotImplementedError
      end

      def graph(workflow_key:)
        raise NotImplementedError
      end

      def definition(workflow_key:, backend: nil, step_variants: {})
        raise NotImplementedError
      end

      def ready_steps(task_id:)
        raise NotImplementedError
      end

      def read_step_context(source_dir:, step_id:, relative_path:)
        raise NotImplementedError
      end

      # Returns `Result.ok(body: String, frontmatter: Hash)` for backends that
      # also surface the optional YAML frontmatter declared at the head of a
      # `.context.md` file. Existing `read_step_context` callers (KOS-155
      # FilesystemRefsCheck, StepContextResolver, bundle_builder) continue to
      # consume the raw body and are unaffected.
      def read_step_context_frontmatter(source_dir:, step_id:, relative_path:)
        raise NotImplementedError
      end

      def seeded_sources
        raise NotImplementedError
      end

      def default_template
        raise NotImplementedError
      end
    end
  end
end
