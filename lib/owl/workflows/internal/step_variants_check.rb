# frozen_string_literal: true

module Owl
  module Workflows
    module Internal
      # Validates the optional `variants:` / `default_variant:` block on a
      # workflow step: variants must be a non-empty mapping, are mutually
      # exclusive with step-level `context` / `context_file`, each variant body
      # must declare a non-empty `context_file`, and `default_variant` must be a
      # non-empty key present in `variants`.
      #
      # Extracted from WorkflowValidator to keep that module focused; mirrors the
      # StepWhenCheck / AllowedChildrenCheck sibling-check pattern.
      module StepVariantsCheck
        module_function

        def call(step, path)
          variants = step['variants']
          default_variant = step['default_variant']

          if default_variant && variants.nil?
            return [error_at("#{path}/default_variant",
                             '`default_variant` requires a `variants:` block on the step.')]
          end
          return [] if variants.nil?

          unless variants.is_a?(Hash) && !variants.empty?
            return [error_at("#{path}/variants",
                             '`variants` must be a non-empty mapping of variant keys to variant bodies.')]
          end

          errors = validate_exclusivity(step, path)
          errors.concat(validate_variant_bodies(variants, path))
          errors.concat(validate_default_variant(default_variant, variants, path))
          errors
        end

        def validate_exclusivity(step, path)
          return [] unless step['context'] || step['context_file']

          [error_at(path, '`variants` is mutually exclusive with the step-level `context` / `context_file`.')]
        end

        def validate_variant_bodies(variants, path)
          variants.flat_map { |name, body| validate_variant_body(body, "#{path}/variants/#{name}") }
        end

        def validate_variant_body(body, vpath)
          return [error_at(vpath, 'Each variant must be a mapping.')] unless body.is_a?(Hash)

          cf = body['context_file']
          return [] if cf.is_a?(String) && !cf.strip.empty?

          [error_at("#{vpath}/context_file",
                    '`context_file` is required on each variant and must be a non-empty string.')]
        end

        def validate_default_variant(default_variant, variants, path)
          unless default_variant.is_a?(String) && !default_variant.strip.empty?
            return [error_at("#{path}/default_variant",
                             '`default_variant` is required when `variants:` is set and must be a non-empty string.')]
          end
          return [] if variants.key?(default_variant)

          [error_at("#{path}/default_variant",
                    "`default_variant: #{default_variant}` is not a key in `variants` " \
                    "(available: #{variants.keys.sort.inspect}).")]
        end

        def error_at(path, message)
          { path: path, message: message }
        end
      end
    end
  end
end
