# frozen_string_literal: true

require_relative '../../result'
require_relative '../../artifacts/api'
require_relative '../../storage/api'
require_relative '../../validation/internal/front_matter_parser'
require_relative 'spec_locator'

module Owl
  module Specs
    module Internal
      # Wires a task's optional `spec_delta` artifact into the P4 delta-merge
      # engine and the P5 trace gate.
      #
      # `merge(root:, task_id:, dry_run:)`:
      #   1. Resolve the task's `spec_delta` path. Absent (artifact undeclared
      #      by the workflow, or the file does not exist) → a graceful skip
      #      `Result.ok(ok: true, applied: false, reason: 'no_spec_delta')`.
      #   2. Read the delta front matter `domain` (missing → `spec_delta_missing_domain`;
      #      slug-invalid → `invalid_domain` via `SpecLocator`).
      #   3. Apply the delta through P4 (`Specs::Api.apply`), propagating the
      #      structural delta errors (`delta_conflict`, `delta_target_missing`,
      #      `invalid_delta`, `merge_would_invalidate`).
      #   4. Gate through P5 (`Specs::Api.trace` with `strict: true`).
      #
      # Returns `Result.ok(ok: trace.valid, applied: !dry_run, domain:, merge:,
      # trace:)`. `ok` is `false` when the trace gate fails (untraced/dangling),
      # but the applied delta is NOT rolled back — the merged spec is the new
      # contract and the trace is the "link tests" signal (design decision).
      #
      # `dry_run: true` delegates to `Specs::Api.apply(dry_run: true)` which
      # writes nothing; the trace then reflects the current on-disk spec and
      # `applied` is reported as `false`.
      #
      # All filesystem access is funneled through `Owl::Storage::Api` /
      # `Owl::Artifacts::Api` — no direct `File`/`Dir`/`Pathname` I/O.
      module TaskMerger
        ARTIFACT_KEY = 'spec_delta'

        module_function

        def merge(root:, task_id:, dry_run: false)
          location = locate_delta(root: root, task_id: task_id)
          return location if location.err?

          data = location.value
          return skipped if data[:skip]

          delta_path = data[:path]
          domain_result = read_domain(delta_path)
          return domain_result if domain_result.err?

          apply_and_trace(root: root, domain: domain_result.value, delta_path: delta_path, dry_run: dry_run)
        end

        # --- internals -----------------------------------------------------

        def apply_and_trace(root:, domain:, delta_path:, dry_run:)
          applied = Owl::Specs::Api.apply(root: root, domain: domain, delta_path: delta_path, dry_run: dry_run)
          return applied if applied.err?

          traced = Owl::Specs::Api.trace(root: root, domain: domain, strict: true)
          return traced if traced.err?

          Result.ok(
            ok: traced.value[:valid],
            applied: !dry_run,
            reason: nil,
            domain: domain,
            merge: applied.value,
            trace: traced.value
          )
        end

        # Resolve the task's spec_delta artifact path. Returns
        # `Result.ok(skip: true)` when the artifact is undeclared by the
        # workflow or the file is absent, `Result.ok(path:)` when present, and
        # `Result.err` only for unexpected failures (e.g. task not found).
        def locate_delta(root:, task_id:)
          resolved = Owl::Artifacts::Api.resolve(root: root, task_id: task_id, artifact_key: ARTIFACT_KEY)
          if resolved.err?
            return Result.ok(skip: true) if resolved.code == :unknown_workflow_artifact

            return resolved
          end

          path = resolved.value[:path]
          return Result.ok(skip: true) unless path && Owl::Storage::Api.exists?(path: path)

          Result.ok(skip: false, path: path)
        end

        def read_domain(delta_path)
          body = Owl::Storage::Api.read(path: delta_path)
          return body if body.err?

          front_matter = Owl::Validation::Internal::FrontMatterParser.parse(body.value)[:front_matter]
          domain = front_matter.is_a?(Hash) ? front_matter['domain'] : nil
          return missing_domain(delta_path) if domain.nil? || domain.to_s.strip.empty?

          valid = SpecLocator.validate_domain(domain)
          return valid if valid.err?

          Result.ok(valid.value)
        end

        def skipped
          Result.ok(ok: true, applied: false, reason: 'no_spec_delta', domain: nil, merge: nil, trace: nil)
        end

        def missing_domain(delta_path)
          Result.err(
            code: :spec_delta_missing_domain,
            message: 'The spec_delta is missing a `domain` front-matter field.',
            details: { path: delta_path.to_s }
          )
        end

        private_class_method :apply_and_trace, :locate_delta, :read_domain, :skipped, :missing_domain
      end
    end
  end
end
