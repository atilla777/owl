# frozen_string_literal: true

require 'time'

require_relative '../../result'
require_relative 'atomic_yaml_writer'
require_relative 'index_rebuilder'
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

          rebuild = IndexRebuilder.rebuild(
            tasks_root: paths_result.value[:tasks],
            index_path: paths_result.value[:index]
          )
          return rebuild if rebuild.err?

          Result.ok(
            task_id: task_id.to_s,
            status: 'abandoned',
            abandoned_at: payload['abandoned_at'],
            abandon_reason: payload['abandon_reason'],
            path: read.value[:path]
          )
        end
      end
    end
  end
end
