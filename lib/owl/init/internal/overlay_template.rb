# frozen_string_literal: true

module Owl
  module Init
    module Internal
      module OverlayTemplate
        module_function

        def for_step(step_id:)
          <<~MARKDOWN
            <!--
            Optional project overlay for the `#{step_id}` step.

            Content of this file is merged into the step's working context
            alongside the built-in workflow context and the current task
            artifacts. Use it to encode project-specific conventions
            (commit format, design rules, review checklist, etc.) without
            editing Owl-shipped templates.

            Delete this file or leave it empty to opt out — Owl skips
            empty overlays.
            -->
          MARKDOWN
        end
      end
    end
  end
end
