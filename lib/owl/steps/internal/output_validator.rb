# frozen_string_literal: true

require_relative '../../result'
require_relative '../../validation/api'
require_relative '../../validation/internal/front_matter_parser'
require_relative '../../workflows/api'
require_relative '../../artifacts/api'
require_relative '../../storage/api'

module Owl
  module Steps
    module Internal
      module OutputValidator
        module_function

        def call(root:, task_id:, step_id:)
          creates_result = collect_creates(root: root, task_id: task_id, step_id: step_id)
          return creates_result if creates_result.err?

          creates = creates_result.value
          return Result.ok([]) if creates.empty?

          results = creates.map { |key| validate_one(root: root, task_id: task_id, key: key) }
          invalid_keys = results.reject { |r| r[:valid] }.map { |r| r[:artifact_key] }
          return Result.ok(results) if invalid_keys.empty?

          Result.err(
            code: :step_outputs_invalid,
            message: "Step '#{step_id}' has invalid output artifacts: #{invalid_keys.join(', ')}.",
            details: { task_id: task_id.to_s, step_id: step_id.to_s, results: results }
          )
        end

        def collect_creates(root:, task_id:, step_id:)
          ready = Owl::Workflows::Api.ready_steps(root: root, task_id: task_id)
          return Result.ok([]) if ready.err?

          definition = Owl::Workflows::Api.definition(root: root, workflow_key: ready.value[:workflow_key])
          return Result.ok([]) if definition.err?

          step = definition.value[:steps][step_id.to_s] || {}
          Result.ok(Array(step['creates'] || step[:creates]))
        end

        def validate_one(root:, task_id:, key:)
          outcome = Owl::Validation::Api.artifact(root: root, task_id: task_id, artifact_key: key)
          return resolution_failure(key, outcome) if outcome.err?

          base = {
            artifact_key: outcome.value[:artifact_key],
            valid: outcome.value[:valid],
            violations: outcome.value[:violations]
          }
          # The completion gate is enforced only here (at `step complete`), not in
          # plain `owl artifact validate`: a draft brief is well-formed but cannot
          # complete its step until the front matter records explicit approval.
          return base unless base[:valid]

          completion = completion_violations(root: root, task_id: task_id, key: key)
          return base if completion.empty?

          { artifact_key: base[:artifact_key], valid: false, violations: base[:violations] + completion }
        end

        def resolution_failure(key, outcome)
          {
            artifact_key: key.to_s,
            valid: false,
            violations: [{
              type: 'resolution_error',
              level: 'error',
              description: outcome.message,
              code: outcome.code.to_s
            }]
          }
        end

        # Enforce an artifact type's optional `validation.completion_front_matter`
        # requirement (e.g. brief => { status: approved }). Inert for
        # well-formedness validation; checked only when a step completes.
        def completion_violations(root:, task_id:, key:)
          resolved = Owl::Artifacts::Api.resolve(root: root, task_id: task_id, artifact_key: key)
          return [] if resolved.err?

          descriptor = resolved.value
          rules = descriptor[:validation] || descriptor['validation'] || {}
          required = rules['completion_front_matter'] || rules[:completion_front_matter]
          return [] unless required.is_a?(Hash) && !required.empty?

          front_matter = read_front_matter(descriptor[:path])
          required.filter_map do |field, expected|
            actual = front_matter[field.to_s]
            next if actual == expected

            {
              type: 'completion_requirement',
              field: field.to_s,
              level: 'error',
              description: "Output '#{key}' requires front matter `#{field}: #{expected}` to complete the step " \
                           "(got #{actual.inspect}). Set it once the artifact is finalised."
            }
          end
        end

        def read_front_matter(path)
          return {} unless path

          read = Owl::Storage::Api.read(path: path)
          return {} if read.err?

          Owl::Validation::Internal::FrontMatterParser.parse(read.value)[:front_matter] || {}
        end
      end
    end
  end
end
