# frozen_string_literal: true

require 'pathname'
require 'yaml'

require_relative '../../result'
require_relative '../../artifacts/api'
require_relative '../../validation/internal/schema_check'
require_relative 'allowed_children_check'
require_relative 'filesystem_refs_check'
require_relative 'graph_builder'
require_relative 'step_context_frontmatter_check'
require_relative 'step_when_check'

module Owl
  module Workflows
    module Internal
      module WorkflowValidator
        ALLOWED_KINDS = %w[task composite_task].freeze
        ALLOWED_SESSION_TYPES = %w[discussion execution].freeze
        ALLOWED_TIERS = %w[standard advanced].freeze

        module_function

        def validate(root:, body:, source_path: nil)
          errors = []
          unless body.is_a?(Hash)
            errors << error_at('/', 'Workflow body must be a YAML mapping (object).')
            return Result.err(
              code: :workflow_validation_failed,
              message: 'Workflow body is not a YAML mapping.',
              details: { errors: errors, source_path: source_path&.to_s }
            )
          end

          Owl::Validation::Internal::SchemaCheck.walk('workflow.json', body).each do |e|
            errors << error_at(e[:path], e[:message], code: e[:keyword])
          end
          errors.concat(validate_top_level(body))
          AllowedChildrenCheck.call(body, root).each do |e|
            errors << error_at(e[:path], e[:message], code: e[:code])
          end
          errors.concat(validate_steps(body, root))

          if errors.empty?
            Result.ok(valid: true, errors: [], source_path: source_path&.to_s)
          else
            Result.err(
              code: :workflow_validation_failed,
              message: 'Workflow definition failed validation.',
              details: { errors: errors, source_path: source_path&.to_s }
            )
          end
        end

        def validate_top_level(body)
          errors = []
          id = body['id']
          unless id.is_a?(String) && !id.strip.empty?
            errors << error_at('/id',
                               'Workflow `id` is required and must be a non-empty string.')
          end

          kind = body['kind']
          if kind && !ALLOWED_KINDS.include?(kind.to_s)
            errors << error_at('/kind',
                               "Workflow `kind` must be one of #{ALLOWED_KINDS.inspect}.")
          end

          title = body['title']
          if title && !title.is_a?(String)
            errors << error_at('/title',
                               'Workflow `title` must be a string when present.')
          end

          artifacts = body['artifacts']
          if artifacts && !artifacts.is_a?(Hash)
            errors << error_at('/artifacts',
                               'Workflow `artifacts` must be a mapping when present.')
          end

          steps = body['steps']
          if steps && !steps.is_a?(Array)
            errors << error_at('/steps',
                               'Workflow `steps` must be an array when present.')
          end

          errors
        end

        def validate_steps(body, root)
          steps = body['steps']
          return [] unless steps.is_a?(Array)

          errors = []
          declared_artifacts = body['artifacts'].is_a?(Hash) ? body['artifacts'].keys.map(&:to_s) : []

          steps.each_with_index do |step, idx|
            errors.concat(validate_step_shape(step, idx))
            errors.concat(StepWhenCheck.call(step, idx, declared_artifacts)) if step.is_a?(Hash)
          end

          graph_result = GraphBuilder.build(steps)
          if graph_result.err?
            errors << error_at('/steps', graph_result.message, code: graph_result.code, details: graph_result.details)
          end

          errors.concat(validate_step_creates(steps, declared_artifacts))
          errors.concat(validate_artifact_refs(body, root))
          errors.concat(validate_plan_gate(steps))

          errors
        end

        # A step declaring `gate: plan_approved` is meaningless without a `plan`
        # step to approve; reject the misconfiguration with a structured error.
        # `children_complete` is intentionally left alone (handled at runtime).
        def validate_plan_gate(steps)
          gated = steps.each_index.select do |idx|
            step = steps[idx]
            step.is_a?(Hash) && step['gate'].to_s == 'plan_approved'
          end
          return [] if gated.empty?

          has_plan = steps.any? { |step| step.is_a?(Hash) && step['id'].to_s == 'plan' }
          return [] if has_plan

          gated.map do |idx|
            error_at(
              "/steps/#{idx}/gate",
              "Step '#{steps[idx]['id']}' declares `gate: plan_approved` but the workflow has no `plan` step.",
              code: :gate_requires_plan
            )
          end
        end

        def validate_step_shape(step, idx)
          path = "/steps/#{idx}"
          return [error_at(path, 'Each step must be a mapping (object).')] unless step.is_a?(Hash)

          errors = []
          id = step['id']
          unless id.is_a?(String) && !id.strip.empty?
            errors << error_at("#{path}/id",
                               'Step `id` is required and must be a non-empty string.')
          end

          errors.concat(validate_step_session(step, path))

          context = step['context']
          context_file = step['context_file']
          if context && context_file
            errors << error_at(path, '`context` and `context_file` are mutually exclusive on a step.')
          end
          if context_file && !(context_file.is_a?(String) && !context_file.strip.empty?)
            errors << error_at("#{path}/context_file", '`context_file` must be a non-empty string when present.')
          end
          if context && !context.is_a?(String)
            errors << error_at("#{path}/context", '`context` must be a string when present.')
          end
          errors.concat(validate_step_variants(step, path))
          errors
        end

        def validate_step_session(step, path)
          errors = []
          session_type = step['session_type']
          if session_type.nil?
            errors << error_at("#{path}/session_type",
                               'Step `session_type` is required (one of ' \
                               "#{ALLOWED_SESSION_TYPES.inspect}). See RFC #1 §2.")
          elsif !ALLOWED_SESSION_TYPES.include?(session_type.to_s)
            errors << error_at("#{path}/session_type",
                               "Step `session_type` must be one of #{ALLOWED_SESSION_TYPES.inspect} " \
                               "(got #{session_type.inspect}).")
          end

          tier = step['tier']
          if !tier.nil? && !ALLOWED_TIERS.include?(tier.to_s)
            errors << error_at("#{path}/tier",
                               "Step `tier` must be one of #{ALLOWED_TIERS.inspect} when present " \
                               "(got #{tier.inspect}). See RFC #1 §3.")
          end

          errors
        end

        def validate_step_variants(step, path)
          variants = step['variants']
          default_variant = step['default_variant']

          if default_variant && variants.nil?
            return [error_at("#{path}/default_variant",
                             '`default_variant` requires a `variants:` block on the step.')]
          end
          return [] if variants.nil?

          errors = []
          unless variants.is_a?(Hash) && !variants.empty?
            return [error_at("#{path}/variants",
                             '`variants` must be a non-empty mapping of variant keys to variant bodies.')]
          end

          if step['context'] || step['context_file']
            errors << error_at(path,
                               '`variants` is mutually exclusive with the step-level `context` / `context_file`.')
          end

          variants.each do |name, body|
            vpath = "#{path}/variants/#{name}"
            unless body.is_a?(Hash)
              errors << error_at(vpath, 'Each variant must be a mapping.')
              next
            end
            cf = body['context_file']
            unless cf.is_a?(String) && !cf.strip.empty?
              errors << error_at("#{vpath}/context_file",
                                 '`context_file` is required on each variant and must be a non-empty string.')
            end
          end

          unless default_variant.is_a?(String) && !default_variant.strip.empty?
            errors << error_at("#{path}/default_variant",
                               '`default_variant` is required when `variants:` is set and must be a non-empty string.')
            return errors
          end

          unless variants.key?(default_variant)
            errors << error_at("#{path}/default_variant",
                               "`default_variant: #{default_variant}` is not a key in `variants` " \
                               "(available: #{variants.keys.sort.inspect}).")
          end

          errors
        end

        def validate_step_creates(steps, declared_artifacts)
          errors = []
          steps.each_with_index do |step, idx|
            next unless step.is_a?(Hash)

            creates = step['creates']
            next unless creates.is_a?(Array)

            creates.each_with_index do |key, ci|
              unless key.is_a?(String) && !key.empty?
                errors << error_at("/steps/#{idx}/creates/#{ci}", '`creates` entry must be a non-empty string.')
                next
              end
              next if declared_artifacts.include?(key)

              errors << error_at(
                "/steps/#{idx}/creates/#{ci}",
                "Step '#{step['id']}' declares `creates: #{key}` but workflow `artifacts:` does not include '#{key}'."
              )
            end
          end
          errors
        end

        def validate_artifact_refs(body, root)
          declared = body['artifacts']
          return [] unless declared.is_a?(Hash) && root

          available = registry_artifact_keys(root)
          errors = []
          declared.each do |key, descriptor|
            next unless descriptor.is_a?(Hash)

            type_key = descriptor['type']
            next if type_key.nil?

            next if available.include?(type_key.to_s)

            errors << error_at(
              "/artifacts/#{key}/type",
              "Artifact '#{key}' references type '#{type_key}' but that type " \
              'is not declared in the project artifact registry.'
            )
          end
          errors
        end

        def registry_artifact_keys(root)
          listing = Owl::Artifacts::Api.list(root: root)
          return [] if listing.err?

          listing.value.map { |entry| entry[:key].to_s }
        rescue StandardError
          []
        end

        def error_at(path, message, code: nil, details: nil)
          payload = { path: path, message: message }
          payload[:code] = code.to_s if code
          payload[:details] = details if details
          payload
        end

        def validate_filesystem_refs(body:, backend:, source_dir:)
          refs_result = FilesystemRefsCheck.call(body: body, backend: backend, source_dir: source_dir)
          return refs_result if refs_result.err?

          frontmatter_result = StepContextFrontmatterCheck.call(
            body: body, backend: backend, source_dir: source_dir
          )
          return frontmatter_result if frontmatter_result.err?

          if frontmatter_result.value.is_a?(Hash) && frontmatter_result.value[:warnings].is_a?(Array)
            warnings = frontmatter_result.value[:warnings]
            return Result.ok(checked: true, warnings: warnings) unless warnings.empty?
          end

          refs_result
        end
      end
    end
  end
end
