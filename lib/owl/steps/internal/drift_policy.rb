# frozen_string_literal: true

module Owl
  module Steps
    module Internal
      # Resolves the effective drift_policy for a step (RFC #1 §4 follow-up):
      #
      #   - explicit `drift_policy` declared in workflow YAML (block/warn/ignore)
      #   - otherwise the default for the step's session_type
      #     (execution → :block, discussion → :warn)
      #   - `--ignore-modification` user override forces :ignore regardless
      #
      # The resolver lives outside DriftDetector so the CLI commands can keep
      # detection (cheap) separate from policy decisions (cheap, but per-call).
      module DriftPolicy
        POLICIES = %w[block warn ignore].freeze

        # Per-check built-in defaults applied when the step has no explicit
        # `drift_policy:`. For step_context_frontmatter the default is :warn
        # regardless of session_type (Variant 1 is a soft contract; existing
        # `.context.md` files without frontmatter must not break validation
        # before the migration commit lands).
        BUILT_IN_CHECK_DEFAULTS = {
          step_context_frontmatter: :warn
        }.freeze

        module_function

        def for(step_payload, override_ignore: false, check: nil)
          return :ignore if override_ignore

          explicit = step_payload && step_payload['drift_policy']&.to_s
          return explicit.to_sym if POLICIES.include?(explicit)

          return BUILT_IN_CHECK_DEFAULTS.fetch(check) if check && BUILT_IN_CHECK_DEFAULTS.key?(check)

          discussion?(step_payload) ? :warn : :block
        end

        def discussion?(step_payload)
          step_payload && step_payload['session_type'] == 'discussion'
        end

        private_class_method :discussion?
      end
    end
  end
end
