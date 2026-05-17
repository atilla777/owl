# frozen_string_literal: true

require_relative '../result'
require_relative 'internal/default_template'
require_relative 'internal/loader'
require_relative 'internal/validator'

module Owl
  module Config
    module Api
      module_function

      def load(root:)
        outcome = Internal::Loader.load(root: root)

        if outcome[0] == :ok
          Result.ok(outcome[1])
        else
          Result.err(code: outcome[1], message: outcome[2], details: outcome[3] || {})
        end
      end

      def validate(root:)
        load_result = load(root: root)
        return load_result if load_result.err?

        document = load_result.value
        errors = Internal::Validator.validate(document)

        if errors.empty?
          Result.ok(document)
        else
          Result.err(
            code: :config_validation_failed,
            message: "Config validation failed with #{errors.length} error(s)",
            details: { errors: errors, document: document }
          )
        end
      end

      def default_template(project_id:)
        Internal::DefaultTemplate.render(project_id: project_id)
      end
    end
  end
end
