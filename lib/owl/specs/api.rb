# frozen_string_literal: true

require_relative '../result'
require_relative '../artifacts/api'
require_relative '../validation/internal/artifact_runner'
require_relative 'internal/spec_locator'

module Owl
  module Specs
    # Public facade for project-level, domain-addressed specs persisted at
    # `specs/<domain>/spec.md` under the `specs` storage role.
    #
    # This surface is read/resolve/validate only — writing/merging spec content
    # is delivered by a later task. Every method returns an `Owl::Result`.
    #
    # `validate` reuses the shared artifact validation runner so a spec is held
    # to the same Requirement/Scenario grammar as the `spec` artifact type
    # (`Owl::Validation::Internal::ArtifactRunner`), per the approved design.
    module Api
      module_function

      def path(root:, domain:)
        Internal::SpecLocator.path(root: root, domain: domain)
      end

      def list(root:)
        Internal::SpecLocator.list(root: root)
      end

      def show(root:, domain:)
        Internal::SpecLocator.read(root: root, domain: domain)
      end

      def validate(root:, domain:)
        located = Internal::SpecLocator.read(root: root, domain: domain)
        return located if located.err?

        type = Owl::Artifacts::Api.find(root: root, key: 'spec')
        return type if type.err?

        violations = Owl::Validation::Internal::ArtifactRunner.validate(descriptor(located.value, type.value))
        Result.ok(
          domain: located.value[:domain],
          path: located.value[:path],
          valid: blocking_count(violations).zero?,
          violations: violations
        )
      end

      def descriptor(located, type)
        {
          key: 'spec',
          path: located[:path],
          exists: true,
          validation: type[:validation],
          front_matter: type[:front_matter]
        }
      end

      def blocking_count(violations)
        violations.count { |violation| (violation[:level] || violation['level']).to_s == 'error' }
      end

      private_class_method :descriptor, :blocking_count
    end
  end
end
