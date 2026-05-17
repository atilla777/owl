# frozen_string_literal: true

require_relative '../../result'
require_relative '../../artifacts/api'
require_relative '../../tasks/api'
require_relative '../../workflows/api'

module Owl
  module Steps
    module Internal
      module InvocationBuilder
        SCHEMA_VERSION = 1

        module_function

        def call(root:, task_id:, step_id:)
          ready = Owl::Workflows::Api.ready_steps(root: root, task_id: task_id)
          return ready if ready.err?

          gate = ensure_ready(ready: ready, task_id: task_id, step_id: step_id)
          return gate if gate

          task_result = Owl::Tasks::Api.inspect(root: root, task_id: task_id)
          return task_result if task_result.err?

          definition_result = Owl::Workflows::Api.definition(root: root, workflow_key: ready.value[:workflow_key])
          return definition_result if definition_result.err?

          assemble(
            root: root, task_id: task_id, step_id: step_id,
            task_payload: task_result.value[:payload],
            workflow_key: ready.value[:workflow_key],
            definition: definition_result.value
          )
        end

        def ensure_ready(ready:, task_id:, step_id:)
          ready_ids = ready.value[:ready].map { |s| s[:id] }
          return nil if ready_ids.include?(step_id.to_s)

          Result.err(
            code: :step_not_ready,
            message: "Step '#{step_id}' is not in the ready set for task '#{task_id}'.",
            details: { task_id: task_id.to_s, step_id: step_id.to_s, ready_steps: ready_ids }
          )
        end

        def assemble(root:, task_id:, step_id:, task_payload:, workflow_key:, definition:)
          step = definition[:steps][step_id.to_s] || { 'id' => step_id.to_s }
          inputs = build_artifacts(root: root, task_id: task_id, keys: input_keys(step, definition))
          outputs = build_artifacts(root: root, task_id: task_id, keys: step['creates'] || [])

          Result.ok(
            schema_version: SCHEMA_VERSION,
            task: task_descriptor(task_payload, root: root, workflow_key: workflow_key),
            step: step_descriptor(step),
            inputs: { artifacts: inputs },
            outputs: { artifacts: outputs }
          )
        end

        def input_keys(step, definition_value)
          requires = step['requires'] || []
          uses_if_present = step['uses_if_present'] || []
          step_lookup = definition_value[:steps]

          from_requires = requires.flat_map do |req|
            (step_lookup[req] || {}).fetch('creates', [])
          end

          (from_requires + uses_if_present).uniq
        end

        def build_artifacts(root:, task_id:, keys:)
          keys.each_with_object({}) do |key, memo|
            descriptor = Owl::Artifacts::Api.resolve(root: root, task_id: task_id, artifact_key: key)
            memo[key.to_s] = if descriptor.ok?
                               descriptor.value
                             else
                               error_artifact_entry(key: key, descriptor: descriptor)
                             end
          end
        end

        def error_artifact_entry(key:, descriptor:)
          {
            key: key.to_s,
            unresolved: true,
            error: { code: descriptor.code.to_s, message: descriptor.message, details: descriptor.details }
          }
        end

        def task_descriptor(payload, root:, workflow_key:)
          {
            id: payload['id'].to_s,
            title: payload['title'].to_s,
            kind: (payload['kind'] || 'task').to_s,
            workflow_key: workflow_key.to_s,
            parent_id: payload['parent_id'],
            children: child_ids(root: root, parent_id: payload['id'])
          }
        end

        def child_ids(root:, parent_id:)
          list_result = Owl::Tasks::Api.list(root: root)
          return [] if list_result.err?

          list_result.value[:tasks].filter_map do |entry|
            next unless entry.is_a?(Hash)

            entry['id'].to_s if entry['parent_id'].to_s == parent_id.to_s
          end
        end

        def step_descriptor(step)
          {
            id: step['id'].to_s,
            title: step['title'],
            skill: step['skill'],
            status: 'ready',
            requires: Array(step['requires']),
            creates: Array(step['creates']),
            uses_if_present: Array(step['uses_if_present'])
          }
        end
      end
    end
  end
end
