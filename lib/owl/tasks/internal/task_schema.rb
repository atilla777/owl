# frozen_string_literal: true

require_relative '../../result'
require_relative '../../validation/internal/schema_check'

module Owl
  module Tasks
    module Internal
      # Schema-validation primitive for task.yaml payloads. Reuses the same
      # JSON-schema walker that validates workflow.json / artifact.json, loaded
      # from the bundled `schemas/task.json`.
      module TaskSchema
        SCHEMA_NAME = 'task.json'

        # Statuses a user may set explicitly through `owl task set-status`.
        # `archived` / `abandoned` are excluded here because they are owned by
        # the archive / abandon flows, but they remain valid persisted values in
        # the schema enum so existing task.yaml files keep validating.
        SETTABLE_STATUSES = %w[open in_progress blocked on_hold done].freeze

        module_function

        # Validate a task payload against schemas/task.json. Returns Result.ok
        # on success, or Result.err(:task_schema_invalid) carrying the walker
        # violations.
        def validate(payload)
          errors = Owl::Validation::Internal::SchemaCheck.walk(SCHEMA_NAME, payload)
          return Result.ok(valid: true) if errors.empty?

          Result.err(
            code: :task_schema_invalid,
            message: "task.yaml failed schema validation: #{errors.map { |e| e[:message] }.join('; ')}",
            details: { errors: errors }
          )
        end

        def settable_status?(status)
          SETTABLE_STATUSES.include?(status.to_s)
        end
      end
    end
  end
end
