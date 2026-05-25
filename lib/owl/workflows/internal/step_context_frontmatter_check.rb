# frozen_string_literal: true

require_relative '../../result'
require_relative '../../steps/internal/drift_policy'
require_relative '../../validation/internal/schema_check'

module Owl
  module Workflows
    module Internal
      # Validates the optional YAML frontmatter declared at the head of each
      # `.context.md` file referenced from a workflow step. Runs AFTER
      # FilesystemRefsCheck (KOS-155): if KOS-155 already reported an error
      # for a given context_file (escape / not_found), this check is not
      # invoked for that file. Per-step `drift_policy:` (KOS-152) gates
      # whether mismatches surface as errors or warnings; the built-in
      # default for this check is :warn (see DriftPolicy::BUILT_IN_CHECK_DEFAULTS).
      module StepContextFrontmatterCheck
        CHECK_KEY = :step_context_frontmatter
        SCHEMA_NAME = 'step_context_frontmatter.json'

        module_function

        def call(body:, backend:, source_dir:, root: nil) # rubocop:disable Lint/UnusedMethodArgument
          return Result.ok(skipped: true) if backend.nil? || source_dir.nil?

          steps = body['steps']
          return Result.ok(checked: true, errors: [], warnings: []) unless steps.is_a?(Array)

          errors = []
          warnings = []

          steps.each_with_index do |step, idx|
            next unless step.is_a?(Hash)

            step_id = step['id'].to_s
            next if step_id.empty?

            collect_step_level(step, idx, backend, source_dir, errors, warnings)
            collect_variants(step, idx, backend, source_dir, errors, warnings)
          end

          if errors.empty?
            Result.ok(checked: true, errors: [], warnings: warnings)
          else
            Result.err(
              code: :workflow_validation_failed,
              message: 'Workflow step_context_frontmatter validation failed.',
              details: { errors: errors, warnings: warnings, source: CHECK_KEY.to_s }
            )
          end
        end

        def collect_step_level(step, idx, backend, source_dir, errors, warnings)
          return if step['variants'].is_a?(Hash) && !step['variants'].empty?

          context_file = step['context_file']
          return unless context_file.is_a?(String) && !context_file.strip.empty?

          process_file(
            step: step,
            variant_name: nil,
            locator: "/steps/#{idx}/context_file",
            relative_path: context_file,
            backend: backend, source_dir: source_dir,
            errors: errors, warnings: warnings
          )
        end

        def collect_variants(step, idx, backend, source_dir, errors, warnings)
          variants = step['variants']
          return unless variants.is_a?(Hash)

          variants.each do |variant_name, vbody|
            next unless vbody.is_a?(Hash)

            context_file = vbody['context_file']
            next unless context_file.is_a?(String) && !context_file.strip.empty?

            process_file(
              step: step,
              variant_name: variant_name.to_s,
              locator: "/steps/#{idx}/variants/#{variant_name}/context_file",
              relative_path: context_file,
              backend: backend, source_dir: source_dir,
              errors: errors, warnings: warnings
            )
          end
        end

        def process_file(step:, variant_name:, locator:, relative_path:,
                         backend:, source_dir:, errors:, warnings:)
          read = backend.read_step_context_frontmatter(
            source_dir: source_dir, step_id: step['id'].to_s, relative_path: relative_path
          )

          if read.err?
            return if filesystem_ref_error?(read.code)

            push_violation(
              step: step, locator: locator, errors: errors, warnings: warnings,
              code: read.code.to_s.to_sym, message: read.message
            )
            return
          end

          frontmatter = read.value[:frontmatter] || {}
          if frontmatter.empty?
            push_violation(
              step: step, locator: locator, errors: errors, warnings: warnings,
              code: :step_context_frontmatter_missing,
              message: "Step '#{step['id']}' context_file '#{relative_path}' has no YAML frontmatter."
            )
            return
          end

          collect_schema_violations(
            frontmatter: frontmatter, step: step, locator: locator,
            errors: errors, warnings: warnings
          )
          collect_field_violations(
            frontmatter: frontmatter, step: step, variant_name: variant_name,
            locator: locator, errors: errors, warnings: warnings
          )
        end

        def collect_schema_violations(frontmatter:, step:, locator:, errors:, warnings:)
          violations = Owl::Validation::Internal::SchemaCheck.walk(SCHEMA_NAME, frontmatter)
          violations.each do |v|
            push_violation(
              step: step, locator: locator, errors: errors, warnings: warnings,
              code: schema_violation_code(v),
              message: "#{locator}: frontmatter #{v[:path]}: #{v[:message]}"
            )
          end
        end

        def schema_violation_code(violation)
          case violation[:keyword]
          when 'additionalProperties' then :step_context_frontmatter_additional_property
          else :step_context_frontmatter_schema_violation
          end
        end

        def collect_field_violations(frontmatter:, step:, variant_name:, locator:, errors:, warnings:)
          check_step_id(frontmatter, step, locator, errors, warnings)
          check_session_type(frontmatter, step, locator, errors, warnings)
          check_variants_applicability(
            frontmatter: frontmatter, step: step, variant_name: variant_name,
            locator: locator, errors: errors, warnings: warnings
          )
        end

        def check_step_id(frontmatter, step, locator, errors, warnings)
          declared = frontmatter['step_id']
          return unless declared.is_a?(String) && !declared.empty?
          return if declared == step['id'].to_s

          push_violation(
            step: step, locator: locator, errors: errors, warnings: warnings,
            code: :step_context_frontmatter_step_id_mismatch,
            message: "step_id '#{declared}' does not match step id '#{step['id']}'."
          )
        end

        def check_session_type(frontmatter, step, locator, errors, warnings)
          declared = frontmatter['applies_to_session_type']
          return unless declared.is_a?(String) && !declared.empty?
          return if declared == step['session_type'].to_s

          push_violation(
            step: step, locator: locator, errors: errors, warnings: warnings,
            code: :step_context_frontmatter_session_type_mismatch,
            message: "applies_to_session_type '#{declared}' does not match step session_type " \
                     "'#{step['session_type']}'."
          )
        end

        def check_variants_applicability(frontmatter:, step:, variant_name:, locator:, errors:, warnings:)
          declared = frontmatter['applies_to_variants']
          return unless declared.is_a?(Array)

          unless step['variants'].is_a?(Hash) && !step['variants'].empty?
            push_violation(
              step: step, locator: locator, errors: errors, warnings: warnings,
              code: :step_context_frontmatter_variants_not_applicable,
              message: "applies_to_variants is declared but step '#{step['id']}' has no variants."
            )
            return
          end

          unknown = declared.reject { |v| step['variants'].key?(v.to_s) }
          unless unknown.empty?
            push_violation(
              step: step, locator: locator, errors: errors, warnings: warnings,
              code: :step_context_frontmatter_unknown_variant,
              message: "applies_to_variants #{declared.inspect} contains unknown variant(s) " \
                       "#{unknown.inspect}; step '#{step['id']}' variants: " \
                       "#{step['variants'].keys.sort.inspect}."
            )
            return
          end

          return if variant_name.nil? || variant_name.empty?
          return if declared.include?(variant_name)

          push_violation(
            step: step, locator: locator, errors: errors, warnings: warnings,
            code: :step_context_frontmatter_unknown_variant,
            message: "applies_to_variants #{declared.inspect} does not include " \
                     "this file's variant '#{variant_name}'."
          )
        end

        def push_violation(step:, locator:, errors:, warnings:, code:, message:)
          policy = Owl::Steps::Internal::DriftPolicy.for(step, check: CHECK_KEY)
          entry = { path: locator, code: code.to_s, message: message }
          case policy
          when :block then errors << entry
          when :warn then warnings << entry
          when :ignore then nil
          end
        end

        def filesystem_ref_error?(code)
          %i[step_context_path_escape step_context_file_not_found].include?(code)
        end
      end
    end
  end
end
