# frozen_string_literal: true

require_relative '../result'
require_relative '../artifacts/api'
require_relative '../storage/api'
require_relative '../validation/internal/artifact_runner'
require_relative 'internal/spec_locator'
require_relative 'internal/merge_engine'
require_relative 'internal/spec_document'
require_relative 'internal/trace_checker'
require_relative 'internal/task_merger'

module Owl
  module Specs
    # Public facade for project-level, domain-addressed specs persisted at
    # `specs/<domain>/spec.md` under the `specs` storage role.
    #
    # This surface is read/resolve/validate only — writing/merging spec content
    # is delivered by a later task. Every method returns an `Owl::Result`.
    #
    # `validate` reuses the shared artifact validation runner so a spec is held
    # to the same Requirement/Scenario grammar as the `spec` artifact type
    # (`Owl::Validation::Internal::ArtifactRunner`), per the approved design.
    module Api
      module_function

      def path(root:, domain:)
        Internal::SpecLocator.path(root: root, domain: domain)
      end

      def list(root:)
        Internal::SpecLocator.list(root: root)
      end

      def show(root:, domain:)
        Internal::SpecLocator.read(root: root, domain: domain)
      end

      def validate(root:, domain:)
        located = Internal::SpecLocator.read(root: root, domain: domain)
        return located if located.err?

        type = Owl::Artifacts::Api.find(root: root, key: 'spec')
        return type if type.err?

        violations = Owl::Validation::Internal::ArtifactRunner.validate(descriptor(located.value, type.value))
        Result.ok(
          domain: located.value[:domain],
          path: located.value[:path],
          valid: blocking_count(violations).zero?,
          violations: violations
        )
      end

      # Compute requirement -> scenario -> test traceability coverage for a
      # domain spec. Read-only: parses the spec and runs `TraceChecker`, never
      # writing. Reuses P1 domain slug-validation and the `spec_not_found` /
      # `invalid_domain` errors. `ok` reflects `strict` — under `--strict` it is
      # the coverage `valid` verdict (no untraced scenarios, no dangling refs);
      # without `strict` it is always `true` (a non-blocking report).
      def trace(root:, domain:, strict: false)
        located = Internal::SpecLocator.read(root: root, domain: domain)
        return located if located.err?

        model = Internal::SpecDocument.parse(located.value[:body])
        report = Internal::TraceChecker.trace(model, root: root)
        Result.ok(
          domain: located.value[:domain],
          path: located.value[:path],
          ok: strict ? report[:valid] : true,
          valid: report[:valid],
          requirements: report[:requirements],
          summary: report[:summary],
          untraced: report[:untraced],
          dangling: report[:dangling],
          unverified: report[:unverified]
        )
      end

      # Compute traceability coverage for an in-memory spec body without reading
      # the filesystem for the spec itself — parses `body` and runs the same
      # `TraceChecker` as `trace`, returning the standard report shape. Used to
      # trace a previewed merge body (`owl spec merge --dry-run`) for a domain
      # whose spec does not yet exist on disk. `ok` mirrors the coverage verdict.
      def trace_body(root:, body:)
        model = Internal::SpecDocument.parse(body)
        report = Internal::TraceChecker.trace(model, root: root)
        Result.ok(
          ok: report[:valid],
          valid: report[:valid],
          requirements: report[:requirements],
          summary: report[:summary],
          untraced: report[:untraced],
          dangling: report[:dangling],
          unverified: report[:unverified]
        )
      end

      # Merge a task's optional `spec_delta` artifact into its domain's living
      # spec and gate on traceability. Resolves the task's `spec_delta`, applies
      # it via the P4 engine (`apply`), then runs the P5 trace with `strict:
      # true` as a gate. When the task declares no delta this is a graceful
      # no-op (`ok: true, applied: false, reason: 'no_spec_delta'`). A trace
      # gate failure returns `ok: false` but does NOT roll back the applied
      # delta. `dry_run: true` previews without writing. Delegates to
      # `Internal::TaskMerger`.
      def merge_task(root:, task_id:, dry_run: false)
        Internal::TaskMerger.merge(root: root, task_id: task_id, dry_run: dry_run)
      end

      # Preview a delta merge without writing: returns the before/after spec
      # bodies, an in-process unified diff, and the merged-body validation
      # verdict. Hard structural errors (`invalid_delta`, `delta_conflict`,
      # `delta_target_missing`, `spec_not_found`, `delta_not_found`,
      # `invalid_domain`) are returned as `Result.err`; a merge that would only
      # invalidate the spec is still previewed with `valid: false`.
      def diff(root:, domain:, delta_path:)
        prepared = Internal::MergeEngine.prepare(root: root, domain: domain, delta_path: delta_path)
        return prepared if prepared.err?

        data = prepared.value
        Result.ok(
          domain: data[:domain],
          path: data[:path],
          before: data[:before],
          after: data[:after],
          unified_diff: data[:unified_diff],
          valid: data[:valid],
          violations: data[:violations],
          applied: data[:applied],
          unchanged: data[:unchanged],
          created: data[:created]
        )
      end

      # Apply a delta to the domain spec. Merges and re-validates fully in
      # memory; on success writes the spec atomically (unless `dry_run`). A
      # merge that would invalidate the spec returns `merge_would_invalidate`
      # with the violations and writes nothing.
      def apply(root:, domain:, delta_path:, dry_run: false)
        prepared = Internal::MergeEngine.prepare(root: root, domain: domain, delta_path: delta_path)
        return prepared if prepared.err?

        data = prepared.value
        return merge_would_invalidate(data) unless data[:valid]

        written = dry_run ? Result.ok(nil) : write_spec(data)
        return written if written.err?

        applied_result(data, dry_run)
      end

      def applied_result(data, dry_run)
        Result.ok(
          domain: data[:domain],
          path: data[:path],
          applied: data[:applied],
          unchanged: data[:unchanged],
          created: data[:created],
          dry_run: dry_run,
          before: data[:before],
          after: data[:after],
          unified_diff: data[:unified_diff]
        )
      end

      def write_spec(data)
        parent = data[:path].rpartition('/').first
        made = Owl::Storage::Api.mkdir_p(path: parent)
        return made if made.err?

        Owl::Storage::Api.write(path: data[:path], contents: data[:after])
      end

      def merge_would_invalidate(data)
        Result.err(
          code: :merge_would_invalidate,
          message: 'Applying the delta would make the spec invalid; nothing was written.',
          details: { domain: data[:domain], path: data[:path], violations: data[:violations] }
        )
      end

      def descriptor(located, type)
        {
          key: 'spec',
          path: located[:path],
          exists: true,
          validation: type[:validation],
          front_matter: type[:front_matter]
        }
      end

      def blocking_count(violations)
        violations.count { |violation| (violation[:level] || violation['level']).to_s == 'error' }
      end

      private_class_method :descriptor, :blocking_count, :applied_result, :write_spec,
                           :merge_would_invalidate
    end
  end
end
