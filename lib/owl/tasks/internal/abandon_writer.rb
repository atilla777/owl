# frozen_string_literal: true

require 'time'

require_relative '../../result'
require_relative 'archive/claim_resetter'
require_relative 'atomic_yaml_writer'
require_relative 'index_writer'
require_relative 'paths'
require_relative 'task_reader'

module Owl
  module Tasks
    module Internal
      module AbandonWriter
        module_function

        def call(root:, task_id:, reason: nil, now: Time.now.utc)
          paths_result = Paths.resolve(root: root)
          return paths_result if paths_result.err?

          read = TaskReader.read(tasks_root: paths_result.value[:tasks], task_id: task_id)
          return read if read.err?

          payload = read.value[:payload]
          if payload['status'] == 'abandoned' && reason.nil?
            return Result.ok(
              task_id: task_id.to_s,
              status: 'abandoned',
              abandoned_at: payload['abandoned_at'],
              abandon_reason: payload['abandon_reason'],
              path: read.value[:path],
              idempotent: true
            )
          end

          payload['status'] = 'abandoned'
          payload['abandoned_at'] = payload['abandoned_at'] || now.iso8601
          payload['abandon_reason'] = reason unless reason.nil?

          AtomicYamlWriter.write(path: read.value[:path], payload: payload)
          persist(root: root, paths: paths_result.value, task_id: task_id, payload: payload, path: read.value[:path])
        end

        def persist(root:, paths:, task_id:, payload:, path:)
          rebuild = IndexWriter.rebuild(root: root, tasks_root: paths[:tasks], index_path: paths[:index])
          return rebuild if rebuild.err?

          Archive::ClaimResetter.delete_if_present(local_state_root: paths[:local_state], task_id: task_id)

          Result.ok(
            task_id: task_id.to_s,
            status: 'abandoned',
            abandoned_at: payload['abandoned_at'],
            abandon_reason: payload['abandon_reason'],
            path: path
          )
        end
      end
    end
  end
end
