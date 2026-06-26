# frozen_string_literal: true

require 'pathname'

require_relative '../../result'
require_relative 'step_context_resolver'
require_relative 'step_lookup'

module Owl
  module Workflows
    module Internal
      # Builds the per-step lookup used by `definition`: the static step map
      # (StepLookup) enriched with each step's resolved `context` body
      # (StepContextResolver, variant-aware).
      module StepsLookupBuilder
        module_function

        def build(steps:, source_path:, backend:, step_variants: {})
          source_dir = Pathname.new(source_path.to_s).dirname

          context_result = StepContextResolver.call(
            steps: steps,
            backend: backend,
            source_dir: source_dir,
            step_variants: step_variants
          )
          return context_result if context_result.err?

          lookup = StepLookup.build(steps)
          context_result.value.each do |step_id, ctx|
            lookup[step_id]['context'] = ctx if lookup.key?(step_id)
          end

          Result.ok(lookup)
        end
      end
    end
  end
end
