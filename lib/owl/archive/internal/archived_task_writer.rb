# frozen_string_literal: true

module Owl
  module Archive
    module Internal
      module ArchivedTaskWriter
        STATUS = 'archived'

        module_function

        def build_payload(task_payload:, now:)
          dup_payload = deep_dup(task_payload)
          dup_payload['status'] = STATUS
          dup_payload['archived_at'] = now.utc.iso8601
          dup_payload
        end

        def deep_dup(value)
          case value
          when Hash
            value.each_with_object({}) { |(k, v), memo| memo[k] = deep_dup(v) }
          when Array
            value.map { |v| deep_dup(v) }
          else
            value
          end
        end
      end
    end
  end
end
