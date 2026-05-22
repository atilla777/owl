# frozen_string_literal: true

module Owl
  module Workflows
    module Internal
      module StepLookup
        STRING_FIELDS = %w[id title skill kind context default_variant session_type tier].freeze
        ARRAY_FIELDS = %w[requires creates uses_if_present].freeze
        BOOLEAN_FIELDS = %w[optional].freeze

        module_function

        def build(steps)
          Array(steps).each_with_object({}) do |step, memo|
            next unless step.is_a?(Hash)

            normalized = normalize(step)
            memo[normalized['id']] = normalized if normalized['id'] && !normalized['id'].empty?
          end
        end

        def normalize(step)
          normalized = {}
          STRING_FIELDS.each do |field|
            value = step[field] || step[field.to_sym]
            normalized[field] = value.to_s if value
          end
          ARRAY_FIELDS.each do |field|
            value = step[field] || step[field.to_sym] || []
            normalized[field] = Array(value).map(&:to_s)
          end
          BOOLEAN_FIELDS.each do |field|
            value = step.key?(field) ? step[field] : step[field.to_sym]
            normalized[field] = value == true unless value.nil?
          end
          variants = step['variants'] || step[:variants]
          normalized['variants'] = normalize_variants(variants) if variants.is_a?(Hash)
          normalized
        end

        def normalize_variants(variants)
          variants.each_with_object({}) do |(name, body), acc|
            next unless body.is_a?(Hash)

            acc[name.to_s] = body.transform_keys(&:to_s)
          end
        end
      end
    end
  end
end
