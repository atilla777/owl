# frozen_string_literal: true

module Owl
  module Locks
    class UnknownBackendError < StandardError; end

    # Public contract for an Owl locks backend.
    #
    # Filesystem is the v1 implementation (see Backends::Filesystem), using a
    # POSIX `O_EXCL` file under the `local_state` role. Future backends (e.g. a
    # row in a shared database for multi-machine coordination) implement the
    # same instance methods. A backend is constructed for a specific repository
    # root. Locks carry a TTL and an owner `token`; there is no heartbeat — a
    # lock is meant to wrap a single short operation and self-heals on expiry.
    module Backend
      def acquire(name:, ttl: nil, token: nil, steal: false)
        raise NotImplementedError
      end

      def release(name:, token:)
        raise NotImplementedError
      end
    end
  end
end
