# frozen_string_literal: true

require 'time'

require_relative '../../result'
require_relative '../../config/api'
require_relative '../../storage/api'
require_relative '../backend'
require_relative '../internal/file_lock'

module Owl
  module Locks
    module Backends
      # Filesystem implementation of `Owl::Locks::Backend`. Resolves the
      # `local_state` storage role (through the Config + Storage facades, so no
      # direct path knowledge lives here) and delegates the O_EXCL mechanics to
      # `Internal::FileLock`.
      class Filesystem
        include Owl::Locks::Backend

        DEFAULT_TTL_SECONDS = 120

        def initialize(root:)
          @root = root
        end

        def acquire(name:, ttl: nil, token: nil, steal: false, now: Time.now.utc)
          local_state = resolve_local_state
          return local_state if local_state.err?

          Internal::FileLock.acquire(
            local_state_root: local_state.value, name: name, ttl: resolve_ttl(ttl),
            token: token, steal: steal, now: now
          )
        end

        def release(name:, token:)
          local_state = resolve_local_state
          return local_state if local_state.err?

          Internal::FileLock.release(local_state_root: local_state.value, name: name, token: token)
        end

        private

        def resolve_local_state
          config = Owl::Config::Api.load(root: @root)
          return config if config.err?

          Owl::Storage::Api.resolve(role: 'local_state', profile: config.value.active_profile, root: @root)
        end

        def resolve_ttl(ttl)
          value = ttl.nil? ? DEFAULT_TTL_SECONDS : ttl.to_i
          value.positive? ? value : DEFAULT_TTL_SECONDS
        end
      end
    end
  end
end
