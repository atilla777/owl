# frozen_string_literal: true

require_relative '../../result'

module Owl
  module Workflows
    module Internal
      module FilesystemRefsCheck
        module_function

        def call(body:, backend:, source_dir:)
          return Result.ok(skipped: true) if backend.nil? || source_dir.nil?

          steps = body['steps']
          return Result.ok(checked: true) unless steps.is_a?(Array)

          errors = []
          steps.each_with_index do |step, idx|
            next unless step.is_a?(Hash)

            step_id = step['id'].to_s
            next if step_id.empty?

            errors.concat(check_step_level(step, idx, step_id, backend, source_dir))
            errors.concat(check_variants(step, idx, step_id, backend, source_dir))
          end

          return Result.ok(checked: true) if errors.empty?

          Result.err(
            code: :workflow_validation_failed,
            message: 'Workflow filesystem refs validation failed.',
            details: { errors: errors }
          )
        end

        def check_step_level(step, idx, step_id, backend, source_dir)
          return [] if step['variants'].is_a?(Hash) && !step['variants'].empty?

          context_file = step['context_file']
          return [] unless context_file.is_a?(String) && !context_file.strip.empty?

          fs_result = backend.read_step_context(
            source_dir: source_dir, step_id: step_id, relative_path: context_file
          )
          return [] if fs_result.ok?

          [error_at("/steps/#{idx}/context_file", fs_result.message, code: fs_result.code)]
        end

        def check_variants(step, idx, step_id, backend, source_dir)
          variants = step['variants']
          return [] unless variants.is_a?(Hash)

          variants.each_with_object([]) do |(name, body), errors|
            next unless body.is_a?(Hash)

            context_file = body['context_file']
            next unless context_file.is_a?(String) && !context_file.strip.empty?

            fs_result = backend.read_step_context(
              source_dir: source_dir, step_id: step_id, relative_path: context_file
            )
            next if fs_result.ok?

            errors << error_at(
              "/steps/#{idx}/variants/#{name}/context_file",
              fs_result.message,
              code: fs_result.code
            )
          end
        end

        def error_at(path, message, code: nil)
          payload = { path: path, message: message }
          payload[:code] = code.to_s if code
          payload
        end
      end
    end
  end
end
