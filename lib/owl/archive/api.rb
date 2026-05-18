# frozen_string_literal: true

require_relative '../tasks/api'

module Owl
  module Archive
    module Api
      module_function

      def archive_task(root:, task_id:, now: Time.now.utc)
        Owl::Tasks::Api.archive(root: root, task_id: task_id, now: now)
      end
    end
  end
end
