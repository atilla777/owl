# frozen_string_literal: true

require_relative '../../result'
require_relative '../../artifacts/api'
require_relative '../../storage/api'
require_relative '../../validation/internal/artifact_runner'
require_relative 'spec_locator'
require_relative 'spec_document'
require_relative 'spec_delta'
require_relative 'delta_merger'
require_relative 'text_diff'

module Owl
  module Specs
    module Internal
      # Orchestrates a full delta merge entirely in memory and hands the result
      # back to `Owl::Specs::Api` for writing.
      #
      # `prepare` performs every read-only step — domain/slug validation, delta
      # read + parse, base spec model (existing or scaffolded), structural merge,
      # serialization, and re-validation of the merged body against the `spec`
      # artifact type — without ever writing. The caller decides whether to
      # persist `:after` based on `:valid`.
      module MergeEngine
        SCAFFOLD = <<~MD
          ---
          status: draft
          summary: Living specification for this domain.
          ---

          # Spec

          ## Purpose

          Describe the verifiable behaviour this domain owns.

          ## Requirements
        MD

        module_function

        def prepare(root:, domain:, delta_path:)
          located = SpecLocator.path(root: root, domain: domain)
          return located if located.err?

          domain = located.value[:domain]
          spec_path = located.value[:path]

          delta = load_delta(delta_path)
          return delta if delta.err?

          merge(root: root, domain: domain, spec_path: spec_path, ops: delta.value)
        end

        # --- internals -----------------------------------------------------

        def merge(root:, domain:, spec_path:, ops:)
          base = base_model(root: root, spec_path: spec_path, domain: domain, ops: ops)
          return base if base.err?

          merged = DeltaMerger.apply(base.value[:model], ops)
          return merged if merged.err?

          after = SpecDocument.serialize(merged.value)
          checked = validate_merged(root: root, body: after, path: spec_path)
          return checked if checked.err?

          summarize(
            domain: domain, spec_path: spec_path, base: base.value,
            after: after, ops: ops, unchanged: merged.value[:unchanged], checked: checked.value
          )
        end

        def summarize(domain:, spec_path:, base:, after:, ops:, unchanged:, checked:)
          before = base[:before]
          Result.ok(
            domain: domain,
            path: spec_path,
            before: before,
            after: after,
            unified_diff: TextDiff.unified(before, after),
            valid: checked[:valid],
            violations: checked[:violations],
            applied: counts(ops, unchanged),
            unchanged: unchanged,
            created: base[:created]
          )
        end

        def load_delta(delta_path)
          return delta_not_found(delta_path) unless Owl::Storage::Api.exists?(path: delta_path)

          body = Owl::Storage::Api.read(path: delta_path)
          return body if body.err?

          SpecDelta.parse(body.value)
        end

        def base_model(root:, spec_path:, domain:, ops:)
          if Owl::Storage::Api.exists?(path: spec_path)
            body = Owl::Storage::Api.read(path: spec_path)
            return body if body.err?

            Result.ok(before: body.value, model: SpecDocument.parse(body.value), created: false)
          elsif ops[:modified].any? || ops[:removed].any?
            SpecLocator.spec_not_found(root: root, domain: domain)
          else
            Result.ok(before: '', model: SpecDocument.parse(SCAFFOLD), created: true)
          end
        end

        def validate_merged(root:, body:, path:)
          type = Owl::Artifacts::Api.find(root: root, key: 'spec')
          return type if type.err?

          descriptor = {
            key: 'spec',
            path: path,
            exists: true,
            validation: type.value[:validation],
            front_matter: type.value[:front_matter]
          }
          violations = Owl::Validation::Internal::ArtifactRunner.validate_body(body, descriptor)
          Result.ok(valid: blocking_count(violations).zero?, violations: violations)
        end

        # Truly-applied changes: declared operations minus idempotent no-ops, so
        # an already-applied (no-op) op is never counted as an applied change.
        # The no-op counts are surfaced separately as `unchanged`.
        def counts(ops, unchanged)
          {
            added: ops[:added].length - unchanged[:added],
            modified: ops[:modified].length - unchanged[:modified],
            removed: ops[:removed].length - unchanged[:removed]
          }
        end

        def blocking_count(violations)
          violations.count { |violation| (violation[:level] || violation['level']).to_s == 'error' }
        end

        def delta_not_found(delta_path)
          Result.err(
            code: :delta_not_found,
            message: "Delta file not found at '#{delta_path}'.",
            details: { path: delta_path.to_s }
          )
        end

        private_class_method :merge, :summarize, :load_delta, :base_model, :validate_merged,
                             :counts, :blocking_count, :delta_not_found
      end
    end
  end
end
