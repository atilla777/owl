# frozen_string_literal: true

require 'pathname'

require_relative '../result'
require_relative 'internal/overlay_paths'
require_relative 'internal/filesystem_source'

module Owl
  module Context
    module Api
      module_function

      # Resolve overlay markdown bodies for a given workflow step.
      #
      # Composition order:
      #   1. universal convention paths (.owl/overlays/<step>.md, docs/ai/<step>.md)
      #   2. variant-specific convention paths when `variant:` is supplied
      #      (.owl/overlays/<step>/<variant>.md, docs/ai/<step>/<variant>.md)
      #   3. explicit paths from .owl/config.yaml `context_overlays.<step>`
      #
      # Empty files and missing paths are silently skipped. Files larger than
      # WARNING_THRESHOLD_BYTES are returned with `warning: :too_long` so the
      # caller can surface it in step logs.
      #
      # Returns Result.ok([{ source:, body:, warning: }, ...]).
      def overlays_for(root:, step_id:, variant: nil)
        paths = Internal::OverlayPaths.collect(root: root, step_id: step_id.to_s, variant: variant)
        overlays = Internal::FilesystemSource.read_all(paths: paths)
        Result.ok(overlays)
      end

      # Enumerate every candidate overlay path for a step (found and missing),
      # in resolution order, for authors debugging which overlays apply.
      # Returns Result.ok([{ path:, present:, bytes: }, ...]).
      def overlay_candidates(root:, step_id:, variant: nil)
        paths = Internal::OverlayPaths.collect(root: root, step_id: step_id.to_s, variant: variant)
        candidates = paths.map do |path|
          present = path.file?
          { path: path.to_s, present: present, bytes: present ? path.size : 0 }
        end
        Result.ok(candidates)
      end
    end
  end
end
