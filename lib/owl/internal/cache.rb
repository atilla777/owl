# frozen_string_literal: true

module Owl
  module Internal
    module Cache
      @store = {}
      @mutex = Mutex.new

      module_function

      def fetch(key, version_token:)
        @mutex.synchronize do
          entry = @store[key]
          return entry[1] if entry && entry[0] == version_token
        end

        fresh_value = yield

        @mutex.synchronize { @store[key] = [version_token, fresh_value] }
        fresh_value
      end

      def clear!
        @mutex.synchronize { @store.clear }
      end
    end
  end
end
