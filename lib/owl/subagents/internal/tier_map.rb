# frozen_string_literal: true

require 'yaml'

module Owl
  module Subagents
    module Internal
      # Resolves an abstract tier name ("standard"/"advanced") to an opaque
      # model identifier defined in an env-specific config. The Owl repo
      # never hardcodes model names; the mapping is per-environment
      # (RFC #1 §3, knowledge entry 46).
      module TierMap
        class ConfigMissing < StandardError
        end

        class MalformedConfig < StandardError
        end

        class UnknownTier < StandardError
        end

        DEFAULT_CONFIG_PATH = '~/.config/owl/tier_map.yaml'

        module_function

        # @param tier_name [String, Symbol] e.g. "standard" or "advanced".
        # @param env [Hash] env-like map; defaults to ENV.
        # @param config_path [String, nil] explicit config path override.
        # @return [String] opaque model id from the env-specific config.
        def resolve(tier_name, env: ENV.to_h, config_path: nil)
          path = resolve_path(config_path: config_path, env: env)
          unless File.exist?(path)
            raise ConfigMissing,
                  "tier_map config not found at #{path}. Create it from " \
                  'docs/examples/tier_map.example.yaml.'
          end

          mapping = load_mapping(path)
          value = mapping[tier_name.to_s]
          raise UnknownTier, "tier '#{tier_name}' not declared in #{path}." if value.nil?

          value.to_s
        end

        def resolve_path(config_path:, env:)
          return config_path if config_path
          return env['OWL_TIER_MAP_PATH'] if env['OWL_TIER_MAP_PATH'] && !env['OWL_TIER_MAP_PATH'].to_s.empty?

          File.expand_path(DEFAULT_CONFIG_PATH)
        end

        def load_mapping(path)
          data = begin
            YAML.safe_load_file(path)
          rescue Psych::SyntaxError => e
            raise MalformedConfig, "tier_map YAML at #{path} is invalid: #{e.message}"
          end
          raise MalformedConfig, "tier_map at #{path} must be a YAML mapping." unless data.is_a?(Hash)

          mapping = data['tier_map']
          unless mapping.is_a?(Hash)
            raise MalformedConfig,
                  "tier_map at #{path} must contain a `tier_map:` mapping " \
                  "(got #{mapping.class.name})."
          end

          mapping
        end

        private_class_method :resolve_path, :load_mapping
      end
    end
  end
end
