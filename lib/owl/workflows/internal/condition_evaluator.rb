# frozen_string_literal: true

require_relative '../../result'
require_relative '../../artifacts/api'
require_relative '../../storage/api'

module Owl
  module Workflows
    module Internal
      # Evaluates a step's `when:` predicate against the body of a prior task
      # artifact. This is the layer that has `root`, so the pure `ReadyResolver`
      # never has to read artifacts/FS. The artifact body is read through the
      # Artifacts + Storage roles (never raw FS).
      #
      # A missing/undeclared/unreadable artifact yields `met: false` — the safe
      # default: a false predicate auto-skips the step, so this never wedges the
      # workflow. A malformed predicate (bad shape / uncompilable regex) returns
      # `Result.err(:invalid_condition)`; callers may then fail open. `workflow
      # validate` rejects malformed predicates at authoring time.
      module ConditionEvaluator
        OPERATORS = %w[matches not_matches].freeze

        module_function

        def evaluate(root:, task_id:, predicate:)
          return invalid('`when` predicate must be a mapping.') unless predicate.is_a?(Hash)

          artifact_key = fetch(predicate, 'artifact')
          unless artifact_key.is_a?(String) && !artifact_key.strip.empty?
            return invalid('`when.artifact` must be a non-empty string.')
          end

          operator, pattern = operator_for(predicate)
          return invalid('`when` must declare exactly one of `matches` / `not_matches`.') if operator.nil?

          regex = compile(pattern)
          return invalid("`when.#{operator}` is not a valid regex.") if regex.nil?

          body = read_body(root: root, task_id: task_id, artifact_key: artifact_key)
          return Owl::Result.ok(met: false) if body.nil?

          matched = body.match?(regex)
          Owl::Result.ok(met: operator == 'matches' ? matched : !matched)
        end

        def operator_for(predicate)
          present = OPERATORS.select { |op| value_present?(predicate, op) }
          return [nil, nil] unless present.length == 1

          op = present.first
          [op, fetch(predicate, op)]
        end

        def value_present?(predicate, key)
          value = fetch(predicate, key)
          value.is_a?(String) && !value.empty?
        end

        def compile(pattern)
          Regexp.new(pattern)
        rescue RegexpError
          nil
        end

        def read_body(root:, task_id:, artifact_key:)
          descriptor = Owl::Artifacts::Api.resolve(root: root, task_id: task_id, artifact_key: artifact_key)
          return nil if descriptor.err? || !descriptor.value[:exists]

          body = Owl::Storage::Api.read(path: descriptor.value[:path])
          return nil if body.err?

          body.value
        end

        def fetch(predicate, key)
          predicate.key?(key) ? predicate[key] : predicate[key.to_sym]
        end

        def invalid(message)
          Owl::Result.err(code: :invalid_condition, message: message, details: {})
        end
      end
    end
  end
end
