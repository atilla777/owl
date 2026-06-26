# frozen_string_literal: true

require_relative 'cache'

module Owl
  module Internal
    # Stat-keyed memoisation of parsed YAML files, shared by the per-domain
    # `<Domain>::Internal::Cache` wrappers. Each domain passes a distinct `prefix`
    # so cache keys never collide across domains.
    module YamlCache
      module_function

      def fetch_yaml(path, prefix:, &)
        absolute = File.expand_path(path.to_s)
        stat = File.stat(absolute)
        token = [stat.mtime.to_r, stat.size]
        Owl::Internal::Cache.fetch("#{prefix}:#{absolute}", version_token: token, &)
      end
    end
  end
end
