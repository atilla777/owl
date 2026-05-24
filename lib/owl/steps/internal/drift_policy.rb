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

        module_function

        def for(step_payload, override_ignore: false)
          return :ignore if override_ignore

          explicit = step_payload && step_payload['drift_policy']&.to_s
          return explicit.to_sym if POLICIES.include?(explicit)

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
