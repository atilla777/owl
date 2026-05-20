# frozen_string_literal: true

require_relative '../../result'
require_relative '../../artifacts/api'
require_relative '../../storage/api'
require_relative 'front_matter_parser'
require_relative 'front_matter_validator'
require_relative 'patterns_checker'
require_relative 'sections_checker'

module Owl
  module Validation
    module Internal
      module ArtifactRunner
        module_function

        def call(root:, task_id:, artifact_key:)
          resolved = Owl::Artifacts::Api.resolve(root: root, task_id: task_id, artifact_key: artifact_key)
          return resolved if resolved.err?

          descriptor = resolved.value
          violations = validate(descriptor)

          Result.ok(
            artifact_key: descriptor[:key],
            valid: blocking_count(violations).zero?,
            violations: violations,
            descriptor: descriptor
          )
        end

        def validate(descriptor)
          path = descriptor[:path]
          return [missing_artifact_violation(path)] unless descriptor[:exists] && path && exists?(path)

          read_result = Owl::Storage::Api.read(path: path)
          return [missing_artifact_violation(path)] if read_result.err?

          body = read_result.value
          fm_result = FrontMatterParser.parse(body)
          violations = []
          violations.concat(front_matter_violations(descriptor, fm_result))

          rules = descriptor[:validation] || {}
          sections = rules['required_sections'] || rules[:required_sections]
          patterns = rules['required_patterns'] || rules[:required_patterns]
          violations.concat(SectionsChecker.check(fm_result[:body], sections))
          violations.concat(PatternsChecker.check(fm_result[:body], patterns))

          violations
        end

        def exists?(path)
          Owl::Storage::Api.exists?(path: path)
        end

        def front_matter_violations(descriptor, fm_result)
          fm_schema = descriptor[:front_matter] || {}
          return [] unless fm_schema.is_a?(Hash) && !fm_schema.empty?

          return [front_matter_parse_violation(fm_result[:error])] if fm_result[:error]

          if fm_result[:front_matter].nil?
            return [front_matter_missing_violation] if front_matter_required?(fm_schema)

            return []
          end

          FrontMatterValidator.validate(fm_result[:front_matter], fm_schema)
        end

        def front_matter_required?(schema)
          required = schema['required'] || schema[:required]
          required.is_a?(Array) && !required.empty?
        end

        def missing_artifact_violation(path)
          {
            type: 'missing_artifact',
            path: path.to_s,
            level: 'error',
            description: "Artifact file does not exist at '#{path}'."
          }
        end

        def front_matter_missing_violation
          {
            type: 'front_matter_missing',
            level: 'error',
            description: 'Front matter is required but absent.'
          }
        end

        def front_matter_parse_violation(error_kind)
          {
            type: 'front_matter_parse_error',
            error: error_kind.to_s,
            level: 'error',
            description: "Front matter could not be parsed (#{error_kind})."
          }
        end

        def blocking_count(violations)
          violations.count { |v| (v[:level] || v['level']).to_s == 'error' }
        end
      end
    end
  end
end
