# frozen_string_literal: true

module Owl
  module Workflows
    module Internal
      module StepLookup
        STRING_FIELDS = %w[id title skill kind].freeze
        ARRAY_FIELDS = %w[requires creates uses_if_present].freeze

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
          normalized
        end
      end
    end
  end
end
