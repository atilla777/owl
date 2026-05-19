# frozen_string_literal: true

require 'pathname'
require 'yaml'

require_relative '../../result'
require_relative '../../artifacts/api'
require_relative 'graph_builder'

module Owl
  module Workflows
    module Internal
      module WorkflowValidator
        ALLOWED_KINDS = %w[task composite_task].freeze
        SKILL_PATTERN = /\A[Oo]wl-step-[a-z_]+\z/

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

          errors.concat(validate_top_level(body))
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
          end

          graph_result = GraphBuilder.build(steps)
          if graph_result.err?
            errors << error_at('/steps', graph_result.message, code: graph_result.code, details: graph_result.details)
          end

          errors.concat(validate_step_creates(steps, declared_artifacts))
          errors.concat(validate_step_skill_pattern(steps))
          errors.concat(validate_artifact_refs(body, root))

          errors
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

        def validate_step_skill_pattern(steps)
          errors = []
          steps.each_with_index do |step, idx|
            next unless step.is_a?(Hash)

            skill = step['skill']
            next if skill.nil?

            unless skill.is_a?(String) && skill.match?(SKILL_PATTERN)
              errors << error_at("/steps/#{idx}/skill", '`skill` must match /^owl-step-[a-z_]+$/ when present.')
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
      end
    end
  end
end
