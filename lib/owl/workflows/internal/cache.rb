# frozen_string_literal: true

require_relative '../../internal/cache'

module Owl
  module Workflows
    module Internal
      module Cache
        KEY_PREFIX = 'workflow'

        module_function

        def fetch_yaml(path)
          absolute = File.expand_path(path.to_s)
          stat = File.stat(absolute)
          token = [stat.mtime.to_r, stat.size]
          Owl::Internal::Cache.fetch("#{KEY_PREFIX}:#{absolute}", version_token: token) { yield }
        end
      end
    end
  end
end
