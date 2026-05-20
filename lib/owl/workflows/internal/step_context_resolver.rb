# frozen_string_literal: true

require_relative '../../result'

module Owl
  module Workflows
    module Internal
      module StepContextResolver
        module_function

        def call(steps:, backend:, source_dir:, step_variants: {})
          resolved = {}
          variants = normalize_step_variants(step_variants)

          Array(steps).each do |step|
            next unless step.is_a?(Hash)

            step_id = step_id(step)
            next if step_id.nil? || step_id.empty?

            value_result = resolve_step(
              step: step,
              step_id: step_id,
              backend: backend,
              source_dir: source_dir,
              chosen_variant: variants[step_id]
            )
            return value_result if value_result.err?

            value = value_result.value
            resolved[step_id] = value unless value.nil?
          end

          Result.ok(resolved)
        end

        def resolve_step(step:, step_id:, backend:, source_dir:, chosen_variant: nil)
          if step['variants']
            return resolve_variant_step(
              step: step,
              step_id: step_id,
              backend: backend,
              source_dir: source_dir,
              chosen_variant: chosen_variant
            )
          end

          inline_value = step['context'] || step[:context]
          file_value = step['context_file'] || step[:context_file]

          return conflict_error(step_id) if inline_value && file_value
          return Result.ok(inline_value.to_s) if inline_value
          return Result.ok(nil) if file_value.nil?

          file_str = file_value.to_s
          return invalid_file_error(step_id) if file_str.empty?

          backend.read_step_context(
            source_dir: source_dir,
            step_id: step_id,
            relative_path: file_str
          )
        end

        def resolve_variant_step(step:, step_id:, backend:, source_dir:, chosen_variant:)
          variants = step['variants']
          variant_name = (chosen_variant || step['default_variant']).to_s

          return missing_variant_error(step_id, variants.keys) if variant_name.empty?
          return unknown_variant_error(step_id, variant_name, variants.keys) unless variants.key?(variant_name)

          variant_body = variants[variant_name]
          file_value = variant_body.is_a?(Hash) ? variant_body['context_file'] : nil
          file_str = file_value.to_s

          return invalid_variant_file_error(step_id, variant_name) if file_str.empty?

          backend.read_step_context(
            source_dir: source_dir,
            step_id: step_id,
            relative_path: file_str
          )
        end

        def normalize_step_variants(step_variants)
          return {} unless step_variants.is_a?(Hash)

          step_variants.each_with_object({}) do |(k, v), acc|
            next if v.nil?

            acc[k.to_s] = v.to_s
          end
        end

        def conflict_error(step_id)
          Result.err(
            code: :step_context_conflict,
            message: "Step '#{step_id}' defines both 'context' and 'context_file'; choose one.",
            details: {
              step_id: step_id,
              fields: %w[context context_file]
            }
          )
        end

        def invalid_file_error(step_id)
          Result.err(
            code: :invalid_step_context_file,
            message: "Step '#{step_id}' has empty 'context_file'.",
            details: {
              step_id: step_id,
              field: 'context_file'
            }
          )
        end

        def missing_variant_error(step_id, available)
          Result.err(
            code: :missing_step_variant,
            message: "Step '#{step_id}' has `variants:` but no variant was chosen and no `default_variant` is set.",
            details: {
              step_id: step_id,
              available: available.sort
            }
          )
        end

        def unknown_variant_error(step_id, variant_name, available)
          Result.err(
            code: :unknown_step_variant,
            message: "Step '#{step_id}' has no variant '#{variant_name}' " \
                     "(available: #{available.sort.inspect}).",
            details: {
              step_id: step_id,
              variant: variant_name,
              available: available.sort
            }
          )
        end

        def invalid_variant_file_error(step_id, variant_name)
          Result.err(
            code: :invalid_step_context_file,
            message: "Variant '#{variant_name}' of step '#{step_id}' has empty 'context_file'.",
            details: {
              step_id: step_id,
              variant: variant_name,
              field: 'context_file'
            }
          )
        end

        def step_id(step)
          raw = step['id'] || step[:id]
          raw&.to_s
        end
      end
    end
  end
end
