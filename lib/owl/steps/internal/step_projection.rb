# frozen_string_literal: true

module Owl
  module Steps
    module Internal
      # Projects a workflow-definition step (workflow YAML, post-StepLookup) into
      # the JSON contract exposed by ReadyResolver#ready_entry and BundleBuilder.
      #
      # `model_tier` is intentionally exposed under that name (RFC #1 §3 / spec
      # acceptance criterion #5) although the underlying YAML key is `tier`.
      module StepProjection
        TRUTHY_STRINGS = %w[true yes 1].freeze
        FALSY_STRINGS = %w[false no 0].freeze
        SESSION_TYPES = %w[discussion execution].freeze
        MODEL_TIERS = %w[standard advanced].freeze
        DEFAULT_SESSION_TYPE = 'execution'
        DEFAULT_MODEL_TIER = 'standard'

        module_function

        def project(step)
          {
            title: title(step),
            optional: optional(step),
            session_type: session_type(step),
            variants_keys: variants_keys(step),
            model_tier: model_tier(step)
          }
        end

        def title(step)
          value = fetch(step, 'title')
          value.nil? ? '' : value.to_s
        end

        def optional(step)
          value = fetch(step, 'optional')
          return false if value.nil?
          return value if [true, false].include?(value)

          normalized = value.to_s.strip.downcase
          return true if TRUTHY_STRINGS.include?(normalized)
          return false if FALSY_STRINGS.include?(normalized)

          raise ArgumentError,
                "StepProjection.optional: cannot normalize #{value.inspect} to boolean"
        end

        def session_type(step)
          value = fetch(step, 'session_type')
          return DEFAULT_SESSION_TYPE if value.nil?

          str = value.to_s
          return str if SESSION_TYPES.include?(str)

          warn '[owl] StepProjection.session_type: unknown value ' \
               "#{str.inspect}, falling back to #{DEFAULT_SESSION_TYPE.inspect}"
          DEFAULT_SESSION_TYPE
        end

        def variants_keys(step)
          variants = fetch(step, 'variants')
          return [] unless variants.is_a?(Hash)

          variants.keys.map(&:to_s).sort
        end

        def model_tier(step)
          value = fetch(step, 'tier')
          return DEFAULT_MODEL_TIER if value.nil?

          str = value.to_s
          return str if MODEL_TIERS.include?(str)

          warn '[owl] StepProjection.model_tier: unknown value ' \
               "#{str.inspect}, falling back to #{DEFAULT_MODEL_TIER.inspect}"
          DEFAULT_MODEL_TIER
        end

        def fetch(step, key)
          return nil unless step.is_a?(Hash)

          step.key?(key) ? step[key] : step[key.to_sym]
        end
      end
    end
  end
end
