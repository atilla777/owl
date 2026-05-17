# frozen_string_literal: true

module Owl
  module Steps
    module Internal
      module Statuses
        STORED = %w[pending running done skipped blocked failed].freeze
        ALL = (STORED + %w[ready]).freeze
        COMPLETING_FOR_UNBLOCKING = %w[done skipped].freeze
        DEFAULT = 'pending'

        module_function

        def stored?(value)
          STORED.include?(value.to_s)
        end

        def completes_for_unblocking?(value)
          COMPLETING_FOR_UNBLOCKING.include?(value.to_s)
        end
      end
    end
  end
end
