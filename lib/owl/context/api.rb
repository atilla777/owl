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
      #   1. convention paths (.owl/overlays/<step>.md, docs/ai/<step>.md)
      #   2. explicit paths from .owl/config.yaml `context_overlays.<step>`
      #
      # Empty files and missing paths are silently skipped. Files larger than
      # WARNING_THRESHOLD_BYTES are returned with `warning: :too_long` so the
      # caller can surface it in step logs.
      #
      # Returns Result.ok([{ source:, body:, warning: }, ...]).
      def overlays_for(root:, step_id:)
        paths = Internal::OverlayPaths.collect(root: root, step_id: step_id.to_s)
        overlays = Internal::FilesystemSource.read_all(paths: paths)
        Result.ok(overlays)
      end
    end
  end
end
