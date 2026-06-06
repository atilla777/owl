# frozen_string_literal: true

require_relative '../tasks/api'
require_relative 'internal/archive_reader'

module Owl
  module Archive
    module Api
      module_function

      def archive_task(root:, task_id:, now: Time.now.utc)
        Owl::Tasks::Api.archive(root: root, task_id: task_id, now: now)
      end

      def list(root:)
        Internal::ArchiveReader.list(root: root)
      end

      def show(root:, task_id:)
        Internal::ArchiveReader.show(root: root, task_id: task_id)
      end

      def read(root:, task_id:, artifact_key:)
        Internal::ArchiveReader.read(root: root, task_id: task_id, artifact_key: artifact_key)
      end
    end
  end
end
