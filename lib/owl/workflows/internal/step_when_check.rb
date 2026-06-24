# frozen_string_literal: true

module Owl
  module Workflows
    module Internal
      # Validates the optional conditional `when:` predicate on a workflow step:
      # `artifact` non-empty, exactly one of `matches`/`not_matches`, and a
      # compilable Ruby regex. The artifact-not-declared case is a non-fatal
      # stderr warning (the predicate still evaluates at runtime; a missing
      # artifact safely resolves to false), so it never blocks validation.
      #
      # Extracted from WorkflowValidator to keep that module focused; mirrors the
      # AllowedChildrenCheck / FilesystemRefsCheck sibling-check pattern.
      module StepWhenCheck
        OPERATORS = %w[matches not_matches].freeze

        module_function

        def call(step, idx, declared_artifacts)
          predicate = step['when']
          return [] if predicate.nil?

          path = "/steps/#{idx}/when"
          return [error_at(path, '`when` must be a mapping (object) when present.')] unless predicate.is_a?(Hash)

          errors = validate_artifact(predicate, path, step, declared_artifacts)
          errors.concat(validate_operators(predicate, path))
          errors
        end

        def validate_artifact(predicate, path, step, declared_artifacts)
          artifact = predicate['artifact']
          unless artifact.is_a?(String) && !artifact.strip.empty?
            return [error_at("#{path}/artifact", '`when.artifact` is required and must be a non-empty string.')]
          end

          unless declared_artifacts.include?(artifact.to_s)
            warn "[owl] workflow validate: step '#{step['id']}' `when.artifact: #{artifact}` " \
                 'is not a declared `artifacts:` key.'
          end
          []
        end

        def validate_operators(predicate, path)
          present = OPERATORS.select { |op| predicate.key?(op) }
          if present.length != 1
            return [error_at(path, '`when` must declare exactly one of `matches` / `not_matches`.')]
          end

          operator = present.first
          pattern = predicate[operator]
          unless pattern.is_a?(String) && !pattern.empty?
            return [error_at("#{path}/#{operator}", "`when.#{operator}` must be a non-empty regex string.")]
          end

          regex_error(pattern, path, operator)
        end

        def regex_error(pattern, path, operator)
          Regexp.new(pattern)
          []
        rescue RegexpError => e
          [error_at("#{path}/#{operator}", "`when.#{operator}` is not a valid regex: #{e.message}.")]
        end

        def error_at(path, message)
          { path: path, message: message }
        end
      end
    end
  end
end
