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
      # On such a gate-fail the merged spec is persisted AND the delta's
      # front-matter `status` is flipped to `merged`, so a re-run skips
      # (`already_merged`) rather than re-applying; `owl spec trace --strict`
      # remains the authoritative coverage gate.
      #
      # `dry_run: true` delegates to `Specs::Api.apply(dry_run: true)` which
      # writes nothing; the trace then reflects the current on-disk spec and
      # `applied` is reported as `false`.
      #
      # All filesystem access is funneled through `Owl::Storage::Api` /
      # `Owl::Artifacts::Api` — no direct `File`/`Dir`/`Pathname` I/O.
      module TaskMerger
        ARTIFACT_KEY = 'spec_delta'
        FRONT_MATTER_FENCE = "---\n"

        module_function

        def merge(root:, task_id:, dry_run: false)
          location = locate_delta(root: root, task_id: task_id)
          return location if location.err?

          data = location.value
          return skipped if data[:skip]

          delta_path = data[:path]
          meta = read_delta_meta(delta_path)
          return meta if meta.err?

          domain = meta.value[:domain]
          return already_merged(domain) if meta.value[:status].to_s == 'merged'

          apply_and_trace(root: root, domain: domain, delta_path: delta_path, dry_run: dry_run)
        end

        # --- internals -----------------------------------------------------

        def apply_and_trace(root:, domain:, delta_path:, dry_run:)
          applied = Owl::Specs::Api.apply(root: root, domain: domain, delta_path: delta_path, dry_run: dry_run)
          return applied if applied.err?

          traced = trace_merge(root: root, domain: domain, applied: applied.value, dry_run: dry_run)
          return traced if traced.err?

          unless dry_run
            flipped = flip_delta_status(delta_path)
            return flipped if flipped.err?
          end

          merged_result(domain: domain, applied: applied.value, traced: traced.value, dry_run: dry_run)
        end

        # Dry-run traces the previewed merged body (the would-be-created spec),
        # so a brand-new domain previews without a `spec_not_found`. A real
        # apply traces the now-persisted on-disk spec, which is authoritative.
        def trace_merge(root:, domain:, applied:, dry_run:)
          if dry_run
            Owl::Specs::Api.trace_body(root: root, body: applied[:after])
          else
            Owl::Specs::Api.trace(root: root, domain: domain, strict: true)
          end
        end

        def merged_result(domain:, applied:, traced:, dry_run:)
          Result.ok(
            ok: traced[:valid],
            applied: !dry_run,
            reason: dry_run ? nil : 'merged',
            domain: domain,
            merge: applied,
            trace: traced
          )
        end

        # Best-effort flip of the delta's front-matter `status` to `merged`
        # after a successful non-dry-run apply, so a re-run is a clean skip.
        # Edits ONLY the first `---\n…\n---` front-matter block at the line
        # level: replaces the existing `status:` line in place (or appends one
        # when absent) and preserves every other front-matter line AND the
        # markdown body byte-for-byte — a `status:` mention in the body is
        # never touched.
        def flip_delta_status(delta_path)
          read = Owl::Storage::Api.read(path: delta_path)
          return read if read.err?

          rewritten = rewrite_status_line(read.value)
          return Result.ok(nil) if rewritten.nil?

          Owl::Storage::Api.write(path: delta_path, contents: rewritten)
        end

        # Returns the source with the front-matter `status` set to `merged`, or
        # `nil` when there is no leading `---\n…\n---` front-matter block (no
        # write needed). Mirrors `FrontMatterParser`'s fence detection so the
        # closing fence and body bytes are carried over untouched.
        def rewrite_status_line(source)
          return nil unless source.start_with?(FRONT_MATTER_FENCE)

          rest = source[FRONT_MATTER_FENCE.length..]
          end_index = rest.index("\n---\n") || rest.index("\n---")
          return nil unless end_index

          fm_text = rest[0...end_index]
          tail = rest[end_index..] || ''
          FRONT_MATTER_FENCE + front_matter_with_merged_status(fm_text) + tail
        end

        # Surgical, line-level rewrite of a front-matter block's `status:` line.
        def front_matter_with_merged_status(fm_text)
          lines = fm_text.split("\n", -1)
          idx = lines.index { |line| line.match?(/\Astatus\s*:/) }
          if idx
            lines[idx] = 'status: merged'
            lines.join("\n")
          elsif fm_text.empty?
            'status: merged'
          else
            "#{fm_text}\nstatus: merged"
          end
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

        def read_delta_meta(delta_path)
          body = Owl::Storage::Api.read(path: delta_path)
          return body if body.err?

          front_matter = Owl::Validation::Internal::FrontMatterParser.parse(body.value)[:front_matter]
          front_matter = {} unless front_matter.is_a?(Hash)
          domain = front_matter['domain']
          return missing_domain(delta_path) if domain.nil? || domain.to_s.strip.empty?

          valid = SpecLocator.validate_domain(domain)
          return valid if valid.err?

          Result.ok(domain: valid.value, status: front_matter['status'])
        end

        def skipped
          Result.ok(ok: true, applied: false, reason: 'no_spec_delta', domain: nil, merge: nil, trace: nil)
        end

        def already_merged(domain)
          Result.ok(ok: true, applied: false, reason: 'already_merged', domain: domain, merge: nil, trace: nil)
        end

        def missing_domain(delta_path)
          Result.err(
            code: :spec_delta_missing_domain,
            message: 'The spec_delta is missing a `domain` front-matter field.',
            details: { path: delta_path.to_s }
          )
        end

        private_class_method :apply_and_trace, :trace_merge, :merged_result, :flip_delta_status,
                             :rewrite_status_line, :front_matter_with_merged_status, :locate_delta,
                             :read_delta_meta, :skipped, :already_merged, :missing_domain
      end
    end
  end
end
