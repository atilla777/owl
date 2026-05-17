# frozen_string_literal: true

require_relative '../../result'
require_relative '../../workflows/api'

module Owl
  module Tasks
    module Internal
      module WorkflowSnapshot
        module_function

        def snapshot(root:, workflow_key:)
          lookup = Owl::Workflows::Api.find(root: root, key: workflow_key)
          return lookup if lookup.err?

          entry = lookup.value[:entry]
          source = lookup.value[:source]
          body = source.is_a?(Hash) ? (source[:body] || source['body']) : nil

          Result.ok(
            workflow: {
              'key' => entry[:key],
              'version' => entry[:version],
              'source' => entry[:source]
            },
            kind: extract_kind(body),
            steps: extract_array(body, 'steps'),
            artifacts: extract_array(body, 'artifacts')
          )
        end

        def extract_array(body, key)
          return [] unless body.is_a?(Hash)

          value = body[key] || body[key.to_sym]
          value.is_a?(Array) ? value : []
        end

        def extract_kind(body)
          return nil unless body.is_a?(Hash)

          body['kind'] || body[:kind]
        end
      end
    end
  end
end
