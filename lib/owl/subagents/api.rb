# frozen_string_literal: true

require_relative '../result'
require_relative 'internal/filesystem_report_backend'
require_relative 'internal/output_spec'
require_relative 'internal/tier_map'

module Owl
  # Env-agnostic subagent contract (RFC #1, knowledge entry 46).
  #
  # Public surface:
  #
  #   Owl::Subagents::Api.spawn(
  #     root:, task_id:, step_id:,
  #     session_type:, tier:, intent:, context_pack:,
  #     output_spec: nil, budget: nil, secrets_redactor: nil,
  #     backend: nil
  #   ) -> Result.ok(...) | Result.err(...)
  #
  # The contract does not mention Claude Code, Codex, or any specific
  # runtime. Concrete spawn mechanics live in runtime-specific backends
  # (see RFC #1 §8 F-2 — future Codex/OpenCode/Claude Code overlays).
  #
  # The MVP default backend, FilesystemReport, writes the input bundle
  # to `.owl/local/spawns/<task>/<step>.input.yaml` and reads back a
  # report from `.owl/local/reports/<task>/<step>.md` that an external
  # runtime writes via `owl step report --body -` (RFC §5). It returns
  # the standard §4.2 output shape regardless of whether a report
  # already exists.
  module Subagents
    ALLOWED_SESSION_TYPES = %w[discussion execution].freeze
    ALLOWED_TIERS = %w[standard advanced].freeze

    module Api
      module_function

      # @return [Owl::Result::Ok | Owl::Result::Err]
      #   on Ok: value is a Hash with keys `:final_state`, `:report_body`,
      #   `:report_artifacts`, `:tool_usage_summary`, `:error_message`.
      def spawn(root:, task_id:, step_id:, session_type:, tier:, intent:, context_pack:,
                output_spec: nil, budget: nil, secrets_redactor: nil, backend: nil)
        validation = validate_inputs(
          session_type: session_type, tier: tier, intent: intent,
          context_pack: context_pack, output_spec: output_spec
        )
        return validation if validation.err?

        backend_instance = backend || default_backend(root: root)
        bundle = build_bundle(
          session_type: session_type, tier: tier, intent: intent,
          context_pack: context_pack, output_spec: output_spec,
          budget: budget, secrets_redactor: secrets_redactor
        )

        result = backend_instance.run(
          task_id: task_id,
          step_id: step_id,
          input_bundle: bundle,
          output_spec: output_spec
        )
        Result.ok(result)
      end

      def validate_inputs(session_type:, tier:, intent:, context_pack:, output_spec:)
        errors = []
        unless ALLOWED_SESSION_TYPES.include?(session_type.to_s)
          errors << { field: 'session_type',
                      message: "must be one of #{ALLOWED_SESSION_TYPES.inspect} (got #{session_type.inspect})." }
        end
        unless ALLOWED_TIERS.include?(tier.to_s)
          errors << { field: 'tier',
                      message: "must be one of #{ALLOWED_TIERS.inspect} (got #{tier.inspect})." }
        end
        unless intent.is_a?(String) && !intent.strip.empty?
          errors << { field: 'intent',
                      message: 'must be a non-empty string.' }
        end
        errors << { field: 'context_pack', message: 'must be a Hash.' } unless context_pack.is_a?(Hash)
        if !output_spec.nil? && !output_spec.is_a?(Hash)
          errors << { field: 'output_spec', message: 'must be a Hash when present.' }
        end

        return Result.ok(nil) if errors.empty?

        Result.err(code: :invalid_subagent_input,
                   message: 'Subagent spawn inputs failed validation.',
                   details: { errors: errors })
      end

      def build_bundle(session_type:, tier:, intent:, context_pack:, output_spec:, budget:, secrets_redactor:)
        {
          session_type: session_type.to_s,
          tier: tier.to_s,
          intent: intent.to_s,
          context_pack: context_pack,
          output_spec: output_spec || Internal::OutputSpec.default,
          budget: budget,
          secrets_redactor: secrets_redactor
        }
      end

      def default_backend(root:)
        Internal::FilesystemReportBackend.new(root: root)
      end

      private_class_method :validate_inputs, :build_bundle, :default_backend
    end
  end
end
