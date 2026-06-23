# frozen_string_literal: true

require 'pathname'

require_relative '../../result'
require_relative '../../artifacts/api'
require_relative '../../storage/api'
require_relative '../../validation/internal/front_matter_parser'

module Owl
  module Publish
    module Internal
      # Flips a publishable artifact's front-matter `status` from `approved`
      # to `shipped` in the canonical source (`tasks/<ID>/design.md`) BEFORE
      # the Publisher copies it, so the source and the published copy stay
      # consistent (the copy carries `shipped`).
      #
      # A rule is "flippable" when its target artifact-type declares a
      # `status` enum that includes `shipped` (in practice the `design`
      # artifact). The detection is driven by the artifact-type schema, not a
      # hard-coded filename.
      #
      # The flip is a no-op on dry-run, on a missing source, when the source
      # has no front-matter, or when the status is already `shipped` (or any
      # value other than `approved`).
      module StatusFlipper
        APPROVED = 'approved'
        SHIPPED = 'shipped'

        FLIPPED = 'flipped_to_shipped'
        ALREADY = 'already_shipped'
        NOT_APPLICABLE = 'not_applicable'

        FENCE = "---\n"
        STATUS_LINE = /^status:[ \t]*approved[ \t]*\r?$/

        module_function

        # Returns Result.ok(design_status: <string>) on success, or a
        # Result.err when the source flip write fails (so the backend can
        # return BEFORE copying a desynced pair).
        def call(root:, workflow_body:, resolved_rules:, dry_run:)
          return Result.ok(design_status: NOT_APPLICABLE) if dry_run

          rule = flippable_rule(root: root, workflow_body: workflow_body, resolved_rules: resolved_rules)
          return Result.ok(design_status: NOT_APPLICABLE) unless rule

          flip_source(rule)
        end

        def flippable_rule(root:, workflow_body:, resolved_rules:)
          artifacts = workflow_body.is_a?(Hash) ? (workflow_body['artifacts'] || workflow_body[:artifacts]) : nil
          return nil unless artifacts.is_a?(Hash)

          resolved_rules.find do |rule|
            type = artifact_type_for(artifacts: artifacts, from: rule['from'])
            type && ships?(root: root, type: type)
          end
        end

        def artifact_type_for(artifacts:, from:)
          artifacts.each_value do |definition|
            next unless definition.is_a?(Hash)

            storage = definition['storage'] || definition[:storage]
            path = storage.is_a?(Hash) ? (storage['path'] || storage[:path]) : nil
            return (definition['type'] || definition[:type]).to_s if path.to_s == from.to_s
          end
          nil
        end

        def ships?(root:, type:)
          found = Owl::Artifacts::Api.find(root: root, key: type)
          return false if found.err?

          enum = found.value.dig(:front_matter, 'properties', 'status', 'enum')
          enum.is_a?(Array) && enum.include?(SHIPPED)
        end

        def flip_source(rule)
          source = Pathname.new(rule['source_path'])
          return Result.ok(design_status: NOT_APPLICABLE) unless Owl::Storage::Api.exists?(path: source)

          read = Owl::Storage::Api.read(path: source)
          return Result.ok(design_status: NOT_APPLICABLE) if read.err?

          contents = read.value
          status = current_status(contents)
          return Result.ok(design_status: NOT_APPLICABLE) if status.nil?
          return Result.ok(design_status: ALREADY) if status == SHIPPED
          return Result.ok(design_status: NOT_APPLICABLE) unless status == APPROVED

          write_flipped(source: source, contents: contents)
        end

        def current_status(contents)
          parsed = Owl::Validation::Internal::FrontMatterParser.parse(contents)
          front_matter = parsed[:front_matter]
          return nil unless front_matter.is_a?(Hash)

          front_matter['status']
        end

        def write_flipped(source:, contents:)
          rewritten = rewrite_status(contents)
          Owl::Storage::Api.write(path: source, contents: rewritten)
          Result.ok(design_status: FLIPPED)
        rescue StandardError => e
          Result.err(
            code: :design_flip_failed,
            message: "Failed to flip design status to shipped in '#{source}': #{e.message}",
            details: { source_path: source.to_s, error_class: e.class.name }
          )
        end

        # Rewrites only the `status:` line inside the leading front-matter
        # block, leaving key order and the rest of the document byte-identical.
        def rewrite_status(contents)
          return contents unless contents.start_with?(FENCE)

          rest = contents[FENCE.length..]
          end_index = rest.index("\n---")
          return contents unless end_index

          front_matter = rest[0...end_index]
          tail = rest[end_index..]
          "#{FENCE}#{front_matter.sub(STATUS_LINE, 'status: shipped')}#{tail}"
        end
      end
    end
  end
end
