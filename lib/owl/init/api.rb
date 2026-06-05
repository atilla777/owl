# frozen_string_literal: true

require 'json'

require_relative 'internal/scaffolder'
require_relative '../config/api'
require_relative '../skills/internal/seeded_sources'

module Owl
  module Init
    module Api
      module_function

      def scaffold(root:, force: false, agent_targets: nil)
        targets = resolve_targets(root: root, agent_targets: agent_targets)

        result = Internal::Scaffolder.call(root: root, force: force, agent_targets: targets)
        return result if result.err?

        persisted = persist_targets(root: result.value[:root], targets: targets)
        return persisted if persisted.err?

        result
      end

      # Flag wins; otherwise honour the choice persisted on a prior init; else
      # fall back to Claude Code's layout (backward compatible).
      def resolve_targets(root:, agent_targets:)
        return agent_targets if agent_targets

        existing = Owl::Config::Api.read_key(root: root, key: 'settings.agent_targets')
        if existing.ok? && existing.value[:value].is_a?(Array) && !existing.value[:value].empty?
          return existing.value[:value].map(&:to_sym)
        end

        Owl::Skills::Internal::SeededSources::DEFAULT_TARGETS
      end

      def persist_targets(root:, targets:)
        Owl::Config::Api.write_key(
          root: root, key: 'settings.agent_targets', value: targets.map(&:to_s).to_json
        )
      end

      private_class_method :resolve_targets, :persist_targets
    end
  end
end
